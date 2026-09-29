-- Inventory adjustments must use the protected production operation path.
revoke execute on function public.adjust_product_inventory(text,numeric) from public, anon, authenticated;
