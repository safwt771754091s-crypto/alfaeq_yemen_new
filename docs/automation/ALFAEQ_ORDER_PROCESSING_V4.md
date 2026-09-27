# Alfaeq Order Processing v4

## Production flow
1. Authenticated customer calls `create_order`.
2. `create_order` validates/prices the order and creates `orders` + `order_items`.
3. Order creation **does not mutate stock**.
4. The trusted `process-order-inventory` Edge Function calls `reserve_order_inventory`.
5. Reservation locks product rows, checks stock, decrements stock atomically, and writes `inventory_movements.sale_reservation`.
6. The order receives `metadata.inventory_status=reserved`.
7. Merchant transitions to `accepted/preparing/ready_for_pickup` are rejected until inventory is reserved.
8. Cancellation releases the reservation through `release_order_inventory` and writes `sale_reservation_release`.
9. Reservation is idempotent for the same order/product.

## Security
- `reserve_order_inventory` and `release_order_inventory` are service-role only.
- `process-order-inventory` requires a JWT whose role is `service_role`.
- Client applications never receive privileged inventory RPC access.
- Catalog imports never modify stock.

## n8n integration
For `order.created`, the n8n master workflow should call:
`POST /functions/v1/process-order-inventory`
with:
`Authorization: Bearer $vars.ALFAEQ_SUPABASE_SERVICE_ROLE_KEY`
and JSON:
`{"orderId":"{{$json.data.orderId}}"}`

The service-role key must exist only in n8n credentials/variables and never in Flutter or Git.
