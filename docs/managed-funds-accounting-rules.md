# Managed Funds accounting rules

Managed Funds uses a single currency per fund. Money is stored in integer minor units. Optional quantities use thousandths of their unit. For a priced line, the repository multiplies the fixed-point quantity and integer unit price using `BigInt`, then rounds half up once to the currency's smallest unit. A service or other unquantified expense can use a manual total. The sum of the item lines must equal the sum of the payment sources.

|Record|Effect on entrusted cash|Effect on unpaid personal advance|
|---|---:|---:|
|Funding|Increases by the received amount|None|
|Funding reversal|Decreases by the reversed amount|None|
|Purchase|Decreases by its entrusted portion|Increases by its personal portion|
|Merchant refund|Increases by the amount credited to the fund|Decreases by the amount credited to the buyer|
|Direct provider reimbursement|None|Decreases by the amount repaid|
|Reimbursement from fund|Decreases by the amount repaid|Decreases by the same amount|
|Valid reversal|Offsets the original effect|Offsets the original effect|

The dashboard shows net funding, net purchase expenses and funding splits after corrections and merchant refunds. It shows repayments separately from expenses. Available to return is the greater of zero and entrusted cash minus outstanding advances. A shortfall is the unpaid portion that exceeds cash. Phase 1 supports purchase-linked advances as the fund's obligations. There are no additional payable types in this phase.

The operational cash balance must stay nonnegative. To pay more than the available cash, record additional funding or enter the personal portion explicitly. Refunds are limited to the unrefunded portion of the original cash split and the unreimbursed personal portion. An incorrect reimbursement can be reversed before recording a refund to the original personal payer. An adjusted purchase can be corrected after the dependent adjustments have been reversed.

Corrections create linked replacement and offsetting records in one database transaction. Funding replacements are posted before the original funding is reversed, so a valid correction can replace a deposit even after some cash has been spent. Purchase corrections reverse the original purchase before posting the replacement. The original record and all correction links remain in the journal. Personal and group account balances and income and expense totals are independent of these records.
