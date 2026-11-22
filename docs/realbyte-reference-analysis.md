# Realbyte reference analysis

The requested reference is Money Manager Expense & Budget for Android, package `com.realbyteapps.moneymanagerfree`. The cloud network returned HTTP 403 for Google Play and Realbyte’s help center. No current store screenshots were supplied with the written brief. The visual evidence available for this comparison is an independently published Android usability study from November 2023. [Official listing](https://play.google.com/store/apps/details?id=com.realbyteapps.moneymanagerfree) · [Study and package identification](https://github.com/tdimk2023p/final-project-donataVD/tree/0cf350b8edeb453e38963c481cd02cfbb1338cfc)

## What the materials show

Slide 3 compares two apps. The dark keyboard-entry screen on the left has an income heading, back control, star action and a horizontal Income, Expense, Transfer selector. Below it, short left-aligned labels share rows with date/time, account, category, amount and note. Thin rules separate the values. An open account picker sits immediately below the form and offers cash, bank and card. The blue income accent stands apart from the neutral dark surface. The other app in the slide offers voice entry. Its blue header and boxed form are outside this comparison. [Study presentation, slide 3](https://github.com/tdimk2023p/final-project-donataVD/blob/0cf350b8edeb453e38963c481cd02cfbb1338cfc/Donata%20Yulvida_Presentasi%20FP.pptx)

Independent documentation for a Realbyte import tool confirms date, description, amount, category and subcategory data. A companion tool’s Android instructions document a More menu leading to PC Manager. These sources establish terminology and a navigation path. They do not establish the placement of current Android tabs. [Import tool](https://github.com/vatzmehta/MMScript/tree/10fc7df) · [Android companion instructions](https://github.com/shahlaukik/money-manager-mcp/tree/8ac4143)

## MoneyTrack design mapping

|Area|Evidence and implementation decision|
|---|---|
|Navigation|The brief specifies Transactions, Statistics, Accounts and More. Keep four labeled bottom destinations, with Add near the transaction list. Current reference tab placement requires a current screenshot.|
|Calendar and daily list|The brief specifies a seven-column month, daily flows, previous/next month and date drill-down. Use a compact month header, Calendar/Daily controls and a date-grouped ledger. Neither the exact week origin nor current reference geometry was visible in the study.|
|Entry|Follow the observed three-way selector and aligned field rows. Keep MoneyTrack’s decimal handling, account verification and explicit save. Reuse frequent entries as editable drafts.|
|Accounts|Group balances by original currency and expose transfer and wallet history from each account. Exact Realbyte asset group layout was unavailable.|
|Statistics|Use period controls, income/expense category distribution and direct record drill-down. The current reference chart layout was unavailable.|
|Budgets and settings|Group budgets, goals, debts, recurring entries and reports under searchable More destinations. Preserve both wallet plans and the monthly reporting-currency limit. Exact reference budget and settings screens were unavailable.|
|Color, type and density|Use the requested red primary, blue income, red expense and neutral surfaces. Apply compact headers, aligned values, slim rules, scalable fonts and full touch areas. These are MoneyTrack tokens. No sampled Realbyte colors or fonts are claimed.|

The study was inspected for structure only. MoneyTrack uses its existing bundled typefaces and Material icons. No third-party imagery is shipped in the app.

## Comparison with the implementation

The original capture in the study measures 702 × 1600. When scaled to the same display width as the MoneyTrack dark form, both put field values about one quarter of the way from the left. Both expose three transaction types followed by five principal rows. In the historical image the five rows occupy about a quarter of the screen, and in the 390 × 780 MoneyTrack capture they occupy about a third. Reviewing the pair led to flush alignment for date, account and category values and a blue selected Income control. Exact spacing for the reference's other screens and changes in later releases remain unverified. [MoneyTrack dark income form](screenshots/entry-dark-income.png) · [Full comparison](moneytrack-redesign-report.md)
