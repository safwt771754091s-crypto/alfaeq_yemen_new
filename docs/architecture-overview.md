# Architecture Overview

This project is a Flutter-based storefront application deployed through Firebase, with backend business logic and data storage managed in the Firebase ecosystem.

```mermaid
flowchart LR
    User[Customer / Admin User]

    subgraph Client[Flutter Client App]
        App[Flutter App\nlib/main.dart]
        Screens[Screens\nlib/screens]
        Core[Core + Shared Logic\nlib/core]
        Services[Services\nlib/services]
        AI[AI Features\nlib/ai]
        Assets[Static Assets\nassets/]
    end

    subgraph Firebase[Firebase Platform]
        Hosting[Firebase Hosting\nweb build + index.html]
        Firestore[Firestore Database\nfirestore.rules / indexes]
        Functions[Cloud Functions\nfunctions/*.js]
    end

    subgraph Backend[Business Services]
        Catalog[Catalog / Inventory APIs\nfunctions/inventory.js\nfunctions/super_alfaeq_catalog.js]
        Orders[Orders & Checkout\nfunctions/order_checkout.js]
        Users[User / Merchant Admin\nfunctions/admin_users.js\nfunctions/merchant_invites.js]
        WhatsApp[WhatsApp / Messaging\nfunctions/whatsapp.js]
        Currency[Currency Service\nfunctions/currency.js]
    end

    User --> App
    App --> Screens
    App --> Core
    App --> Services
    App --> AI
    App --> Assets

    App -->|Reads / writes app data| Firestore
    App -->|Served via web build| Hosting
    App -->|Calls backend APIs| Functions

    Functions --> Catalog
    Functions --> Orders
    Functions --> Users
    Functions --> WhatsApp
    Functions --> Currency

    Catalog --> Firestore
    Orders --> Firestore
    Users --> Firestore

    Hosting --> App
```

## Components

- Flutter client app: main application UI and business logic located under `lib/`.
- Firebase Hosting: serves the production web bundle from `build/web`.
- Firestore: holds application data and access rules defined in `firestore.rules`.
- Cloud Functions: backend logic for catalog, checkout, user management, merchant invites, WhatsApp notifications, and currency integration.
- Assets: product and catalog data under `assets/` and supporting web/static content.

## Typical request flow

1. User interacts with the Flutter application.
2. App reads configuration and data from Firestore or backend APIs.
3. Cloud Functions process business operations such as inventory updates or order checkout.
4. Results are returned to the client or persisted to Firestore.
5. Firebase Hosting serves the compiled web frontend for browser access.
