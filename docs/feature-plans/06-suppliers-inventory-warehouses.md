# Suppliers, Inventory, and Warehouses

## Goal

Replace abstract per-order ingredient charges with an understandable supply chain: suppliers offer different price/quality/reliability tradeoffs; restaurants and warehouses hold stock; recipes consume ingredients; freshness declines; shortages and logistics affect service.

## Existing foundation

Recipes/dishes already have ingredient cost, orders snapshot cost, restaurants have locations, delivery and traffic systems can route vehicles, and economy supports daily expenses. The initial implementation should preserve current direct-cost behavior as an emergency-purchase fallback while inventory is introduced.

## Data model

- `InventoryItemDef`: ingredient ID, unit, storage class, shelf life, volume, and substitution rules.
- `StockLot`: ingredient ID, quantity, quality, acquired minute, expiry minute, unit cost, supplier ID, and reservation count.
- `InventoryState`: owner type/ID, capacity by storage class, lots, reorder policies, and audit totals.
- `SupplierDef`: city availability, catalog, base quality, price multiplier, reliability, minimum order, lead time, delivery fee, disruption profile, and relationship modifiers.
- `SupplierContractState`: company, supplier, negotiated terms, warehouse destination, active dates, and service history.
- `WarehouseState`: building ID, company, expansion level, capacity, assigned restaurants, inventory, vehicles, and operating costs.
- `PurchaseOrder` and `TransferOrder`: requested items, source/destination, status, ETA, vehicle/aggregate shipment, received quantities, and failure reason.

Use stock lots rather than one average quantity so quality, cost, and freshness remain auditable. Consume first-expiring valid stock by default.

## Supply loop

1. Forecast ingredient need from enabled recipes, recent demand, scheduled events, and safety stock.
2. Create purchase orders manually or through policy.
3. Supplier confirms price, quantity, and ETA based on reliability and city conditions.
4. Shipment enters a warehouse or restaurant inventory.
5. Warehouses create transfer orders to assigned restaurants.
6. Orders reserve and consume recipe ingredients at cooking start.
7. Stock freshness declines; expired stock becomes waste and may create health/inspection risk.
8. Shortage policy chooses substitute, temporarily disables recipe, delays order, or buys expensive emergency retail stock.

Physical vehicles should be used for nearby, visible, or disrupted shipments. Routine off-screen transfers can be aggregated from route time and traffic while producing the same cost and ETA rules.

## Player controls

The Suppliers screen should include:

- Supplier comparison by price, quality, reliability, lead time, fees, and catalog coverage.
- Contract and warehouse assignment.
- Current restaurant/warehouse stock, freshness, days of cover, reserved quantity, inbound orders, and waste.
- Per-ingredient reorder point, target stock, preferred supplier, acceptable quality, and emergency behavior.
- Forecast warnings tied to menu changes, marketing campaigns, or city events.

World and operations views show inbound shipments, stockout warnings, and the ingredient causing a blocked recipe. Avoid requiring the player to order every tomato manually; sensible policies are available from the start.

## Economic and gameplay effects

- High-quality suppliers improve recipe quality but raise unit cost.
- Reliable suppliers reduce safety stock and emergency purchasing.
- Large orders reduce unit/transport cost but increase spoilage and cash tied in inventory.
- Warehouse location changes transfer time and vehicle cost.
- Multiple warehouses allow quality segmentation or geographic coverage.
- Disruptions create opportunities for resilient contracts, substitutes, or menu changes.

## Integrations

- Custom recipes provide bill-of-material requirements.
- `RestaurantManager` reserves/consumes stock and reports shortage reasons.
- `EconomyManager` records purchases, delivery fees, waste, warehouse rent, and emergency buys separately.
- Traffic supplies route ETA; DeliveryManager patterns may be reused but customer and supply deliveries remain distinct queues.
- Managers automate ordering within policy.
- AI companies forecast and procure using the same APIs.
- Reports show food cost, waste, supplier reliability, stock turns, and lost sales.
- Government inspections react to expired or contaminated stock; sabotage may disrupt shipments or introduce pests.

## Delivery phases

### Phase 1 — Restaurant inventory

Add stock lots, recipe consumption, manual restock, emergency fallback, shortage UI, save/load, and accounting.

### Phase 2 — Suppliers

Add competing offers, purchase orders, lead time, quality/reliability, recurring delivery fees, and basic automatic reorder.

### Phase 3 — Warehouses and transfers

Add warehouse properties, capacity/upgrades, restaurant assignments, transfer orders, route ETA, and world shipment visualization.

### Phase 4 — Forecasting and disruptions

Add demand forecasts, menu-aware policies, supplier events, substitution, contract relationships, AI strategy, and detailed reports.

## Acceptance criteria

- Every cooked custom recipe consumes the correct ingredient quantities exactly once.
- Shortages produce explicit recipe/order effects and never create negative inventory.
- Price, quality, lead time, and reliability make at least three supplier strategies viable.
- Freshness and waste are deterministic across time speeds and save/load.
- Warehouse assignment changes delivery time and cost based on actual city routes.
- Automated reorder maintains policy targets without duplicate purchase orders.
- Finance reports reconcile purchases, inventory value, consumption, waste, and emergency buys.

## Testing strategy

- Inventory conservation/property tests for reserve, consume, cancel, spoil, transfer, and load.
- Seeded supplier reliability and disruption tests.
- Forecast tests around menu enable/disable and marketing demand spikes.
- Route/ETA tests with unreachable destinations and traffic changes.
- Migration tests that seed initial stock for old saves so active restaurants do not instantly fail.

## Risks and controls

- **Micromanagement:** policy presets, days-of-cover display, consolidated purchasing, and manager delegation.
- **Simulation cost:** aggregate quantities and shipments; only visible logistics require full agents.
- **Economic shock during migration:** starter inventory and temporary emergency-buy grace period.
- **Cross-system deadlocks:** orders reserve stock only at a clearly defined state and always release reservations on cancellation.

