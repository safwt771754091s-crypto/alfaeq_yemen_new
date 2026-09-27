# Alfaeq Order & Inventory Engine v3

Stage 3 makes inventory reservation an atomic server-side operation for an order.

Flow: order + order_items -> trusted processor -> reserve_order_inventory(order_id) -> row locks -> stock check -> stock update -> inventory movement. Any failure rolls the transaction back.

Safety: catalog imports never modify stock; clients must not mutate inventory for fulfillment; the RPC is executable only by service_role; inventory changes remain auditable; concurrent reservations serialize on product row locks.

Next integration: connect order.created in n8n to a trusted order-processing endpoint/function and emit inventory.reserved or inventory.failed. Never expose the privileged RPC to untrusted clients.
