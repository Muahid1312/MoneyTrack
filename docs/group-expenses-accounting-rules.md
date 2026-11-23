# Group fund accounting

A group holds one currency chosen when it is created. MoneyTrack stores amounts as integer minor units and follows that currency’s precision. Quantities allow three decimal places. The unit-price product is rounded once to the nearest minor unit, with half units rounded up. Expected member contributions and the expected budget are planning amounts.

|Recorded action|Group cash|Expense total|Amount owed|
|---|---:|---:|---|
|Receive a contribution|Increase|Unchanged|Member’s remaining expected contribution falls, down to zero|
|Buy something with group cash|Decrease|Increase|Unchanged|
|Member pays for a purchase|Unchanged|Increase|Group owes that member the purchase price|
|Record an unpaid supplier bill|Unchanged|Increase|Group owes the supplier|
|Pay a reimbursement or supplier bill|Decrease|Unchanged|The linked purchase’s unpaid balance falls|
|Confirm a refund plan|Unchanged|Unchanged|The plan records each member’s entitlement|
|Pay part or all of a refund|Decrease|Unchanged|Member’s unpaid refund falls|
|Member returns a previous refund after reopening|Increase|Unchanged|Lifetime net refunds paid to that member fall|
|Count the physical cash|Unchanged|Unchanged|The signed difference from book cash is recorded|

Cash equals net contributions minus group-cash purchases, actual reimbursements, supplier payments and net refunds paid. Expenses include purchases from all three sources exactly once. Distributable cash equals book cash less unpaid reimbursements and supplier bills. A shortfall is displayed as a deficit. Future expected contributions never enter this calculation.

## Allocation and payment

1. Subtract outstanding obligations from current group cash. Resolve a deficit or a recorded physical cash discrepancy before confirming a plan.
2. Add prior net refunds paid to reconstruct the total lifetime pool when revising a plan. Weight each member by confirmed contributions less contribution reversals. Members with zero net contributions receive zero.
3. Use integer products and division to assign the floor of each proportional share. Award the remaining minor units in descending order of division remainder. A tie goes to the lower permanent member ID. An empty pool allocates zero. A positive pool with no contributors requires reconciliation.
4. Store all shares in a dated, immutable confirmation event. The amount still payable to a member equals the confirmed lifetime share minus their net refunds already paid. In a revised plan, the sum of outstanding refunds matches the remaining distributable cash. If a prior payout exceeds its revised share, the organizer must record money actually returned or correct the underlying records.
5. Each payout uses the confirmed allocation and available surplus, receives a unique journal ID and reduces cash exactly once. A completion entry requires zero cash, zero remaining reimbursements and bills, fully paid refunds and a reconciled cash count if one was recorded.

For the Paghman trip, ten contributions of 300 AFN produce 3,000 AFN. Five purchases totaling 2,350 AFN leave 650 AFN. Each member receives 65 AFN. In the unequal example, contributions of 300, 300, 500 and 200 AFN produce refunds of 92.31, 92.31, 153.84 and 61.54 AFN from a 400 AFN pool.

## Corrections, custody and cancellation

A correction records a reversal with a reason. Editing a contribution or purchase appends its reversal and replacement in one transaction. A receipt stays attached to the source and is carried to the corrected expense unless replaced. A member-funded purchase with any reimbursements paid requires recording the money actually returned before reversing its obligation.

The first financial movement activates a planned group. A cancelled group keeps its entire journal and can pay existing obligations and enter settlement. Reopening a cancelled, settled or completed group requires a reason. Prior confirmations and actual payments remain visible in the history and report.

Keep the entrusted money separate from personal wallet balances. The organizer can count cash on the Settlement tab. A count records the difference on that date. Correct a missing or incorrect posting and count again to clear a discrepancy. Members are local names. No bank transfer or payment is initiated by the app.
