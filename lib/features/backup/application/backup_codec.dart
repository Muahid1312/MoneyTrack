import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../../../data/database/app_database.dart';
import '../../../data/storage/portable_snapshot.dart';
import '../../security/application/security_service.dart';

abstract final class BackupCodec {
  static const magic='MTRKBK01';
  static Future<Uint8List> encrypt(Map<String,dynamic> snapshot,String passphrase) async {
    if(passphrase.runes.length<12||utf8.encode(passphrase).length>1024)throw ArgumentError('Use a backup passphrase of at least 12 characters');
    final salt=SecureCrypto.random(32),nonce=SecureCrypto.random(12);
    final header=utf8.encode(jsonEncode({'format':'moneytrack-backup','version':1,'schema':AppDatabase.schemaVersion,
      'cipher':'AES-256-GCM','kdf':'argon2id','memory':65536,'iterations':3,'parallelism':1,
      'salt':base64Encode(salt),'nonce':base64Encode(nonce),'created_utc':DateTime.now().toUtc().toIso8601String()}));
    final plain=utf8.encode(jsonEncode(snapshot));if(plain.length>PortableSnapshot.maxBytes-4096)throw StateError('Backup exceeds the 32 MiB portable format limit');
    final bytes=await SecureCrypto.derive(passphrase,salt,memory:65536,iterations:3);
    final key=SecretKeyData(bytes,overwriteWhenDestroyed:true);
    try {final box=await AesGcm.with256bits().encrypt(plain,secretKey:key,nonce:nonce,aad:header);
      final length=ByteData(4)..setUint32(0,header.length,Endian.big);
      return Uint8List.fromList([...ascii.encode(magic),...length.buffer.asUint8List(),...header,...box.cipherText,...box.mac.bytes]);
    } finally {key.destroy();bytes.fillRange(0,bytes.length,0);plain.fillRange(0,plain.length,0);}
  }
  static Map<String,dynamic> inspect(List<int> bytes) {
    if(bytes.length<28||bytes.length>PortableSnapshot.maxBytes||ascii.decode(bytes.take(8).toList(),allowInvalid:true)!=magic)throw const FormatException('Unsupported backup');
    final length=ByteData.sublistView(Uint8List.fromList(bytes.sublist(8,12))).getUint32(0,Endian.big);
    if(length<1||length>4096||12+length+16>=bytes.length)throw const FormatException('Invalid header');
    final info=Map<String,dynamic>.from(jsonDecode(utf8.decode(bytes.sublist(12,12+length))) as Map);
    if(info['format']!='moneytrack-backup'||info['version']!=1||info['schema']!=AppDatabase.schemaVersion||info['cipher']!='AES-256-GCM'||info['kdf']!='argon2id'||info['memory']!=65536||info['iterations']!=3||info['parallelism']!=1)throw const FormatException('Unsupported backup parameters');
    return info;
  }
  static Future<Map<String,dynamic>> decrypt(List<int> bytes,String passphrase) async {
    inspect(bytes);
    final length=ByteData.sublistView(Uint8List.fromList(bytes.sublist(8,12))).getUint32(0,Endian.big);
    if(length<1||length>4096||12+length+16>=bytes.length)throw const FormatException('Invalid backup header');
    final header=bytes.sublist(12,12+length);final info=jsonDecode(utf8.decode(header)) as Map;
    if(info['format']!='moneytrack-backup'||info['version']!=1||info['schema']!=AppDatabase.schemaVersion||info['cipher']!='AES-256-GCM'||info['kdf']!='argon2id'||info['memory']!=65536||info['iterations']!=3||info['parallelism']!=1)throw const FormatException('Unsupported backup version or KDF parameters');
    final salt=base64Decode(info['salt'] as String),nonce=base64Decode(info['nonce'] as String);
    if(salt.length!=32||nonce.length!=12||utf8.encode(passphrase).length>1024)throw const FormatException('Invalid backup metadata');
    final derived=await SecureCrypto.derive(passphrase,salt,memory:65536,iterations:3);final key=SecretKeyData(derived,overwriteWhenDestroyed:true);
    List<int>? plain;
    try {plain=List<int>.from(await AesGcm.with256bits().decrypt(SecretBox(bytes.sublist(12+length,bytes.length-16),nonce:nonce,mac:Mac(bytes.sublist(bytes.length-16))),secretKey:key,aad:header));
      if(plain.length>PortableSnapshot.maxBytes)throw const FormatException('Backup too large');return Map<String,dynamic>.from(jsonDecode(utf8.decode(plain)) as Map);
    } finally {key.destroy();derived.fillRange(0,derived.length,0);if(plain!=null)plain.fillRange(0,plain.length,0);}
  }
}
