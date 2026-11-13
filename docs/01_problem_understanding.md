# Google Pay (UPI) Digital Payments Database — Problem Understanding

## 1. Project Overview

Google Pay is a digital payment platform that processes UPI transactions, manages user bank accounts and VPAs, supports merchant payments, and provides services such as rewards and bill payments. As transaction volume and user activity increase, the database must support fast payment operations, reliable data management, and efficient analytical reporting.

The purpose of this project is to design and optimize a PostgreSQL database that can handle current workloads and remain efficient as the dataset grows.

## 2. Business Problems (P1–P8)

- **P1 – Slow Transaction History:** Users experience delays while viewing transaction history and payment details, including VPA and linked bank account information.
- **P2 – UPI Limit Validation:** Payment processing requires quick daily transaction-limit checks to prevent users from exceeding permitted limits.
- **P3 – Reconciliation Delays:** Pending transactions and delayed bank callbacks create difficulties in reconciling payment records.
- **P4 – Merchant Collection and Settlement:** Merchants need accurate information about collections, daily settlements, and merchants who have not received any payments.
- **P5 – Fraud and Risk Detection:** The system must support checks for suspicious transactions, mule accounts, repeated payments, and refunds.
- **P6 – Rewards and Bill Payment Delays:** Reward processing and bill reminder jobs must run efficiently and update the correct records.
- **P7 – Compliance and Dispute Management:** KYC-risk reports and customer dispute queues must be accessible efficiently for compliance and support teams.
- **P8 – Analytics and Scalability:** Bank health dashboards and business reports must continue performing efficiently as the database grows to approximately 20 times its current size.

## 3. Business Need and Stakeholders

The database should provide reliable payment operations, maintain data consistency, reduce query execution time, and support future growth.

Key stakeholders include:
- **Customers:** Need fast and reliable payment history and transaction services.
- **Merchants:** Need collection and settlement information.
- **Payments and Operations Teams:** Need transaction validation and reconciliation.
- **Fraud and Risk Teams:** Need suspicious activity detection.
- **Rewards and Bill Payment Teams:** Need efficient reward and reminder processing.
- **Compliance and Support Teams:** Need KYC-risk reports and dispute information.
- **Bank Partnership and Analytics Teams:** Need bank health dashboards and business insights.

## 4. Workload Classification

**Customer-facing and real-time operations:** P1, P2, P3, P6 payment operations, and relevant transaction checks. These require low response times because they directly affect payment processing and customer experience.

**Reporting and analytical operations:** P4 merchant reports, P5 fraud analysis, P6 reward and bill reports, P7 compliance reports, and P8 business analytics. These workloads involve data analysis, reporting, and batch processing.

## 5. Initial Assumptions

- PostgreSQL is used as the relational database management system.
- The supplied CSV files represent the initial dataset.
- Primary keys and foreign keys will be used to maintain relationships and data integrity.
- Constraints will be designed according to the supplied data and business rules.
- Query results must remain correct after optimization.
- The database should be evaluated on both the initial dataset and a future dataset approximately 20 times larger.