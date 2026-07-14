# Editable Restaurant Interiors

## Goal

Turn restaurant interiors from a visual operations viewer into a buildable management space. Players should control capacity, production throughput, atmosphere, style, maintenance, and customer flow by placing furniture and equipment, while still being able to watch cooks, waiters, drivers, and guests use the result.

## Existing foundation

`RestaurantInteriorView` already renders operational actors, stations, tables, queues, meals, and deliveries. `RestaurantState` already tracks table count, queues, kitchen work, dining, and sales. The implementation should preserve those systems and replace fixed slots with a persistent layout that generates usable stations, seats, paths, and visual anchors.

## Data model

- `FurnitureDef`: ID, category, price, resale curve, footprint, interaction anchors, capacity contribution, throughput, durability, style tags, demographic appeal, comfort, entertainment, cleanliness impact, maintenance cost, prerequisites, scene path, and collision metadata.
- `PlacedFurnitureState`: stable instance ID, definition ID, transform/grid coordinates, color/material variant, durability, cleanliness, enabled state, and room assignment.
- `InteriorLayoutState`: restaurant ID, floor/wall finishes, music choice, expansion level, placed instances, kitchen/dining polygons, and layout revision.
- `InteriorEvaluation`: seats, cook stations, waiter paths, queue capacity, accessibility, style coherence, demographic appeal, bottlenecks, and safety/validation issues.

Use a logical placement grid and normalized room coordinates independent of the display scene. Runtime nodes are generated from state and are never the only copy of the layout.

## Placement and validation

The editor must support place, move, rotate, recolor, duplicate, sell, repair, and multi-select. Every operation runs validation before committing:

- Inside the legal room polygon and expansion boundary.
- No footprint overlap or blocked entrance/exit.
- Required interaction anchors reachable by staff and customers.
- Tables paired with usable chairs; ovens placed in kitchen zones.
- Minimum aisle width and queue path preserved.
- Clear feedback for invalid placement and the blocking object.

Rebuild navigation only after a committed batch, not continuously while dragging. Use inexpensive footprint checks for previews and full reachability validation on commit.

## Gameplay effects

- Tables and chairs determine actual dine-in capacity.
- Ovens and prep stations determine concurrent cooking slots and speed.
- Counters, pickup racks, and queue barriers influence order flow.
- Comfort, decoration, entertainment, finishes, music, and style coherence affect demographic appeal and patience.
- Crowding and long paths reduce service throughput.
- Furniture durability decays through use; poor condition reduces appeal and can fail inspections.
- Cleanliness depends on traffic, staff/contractors, and closure time.
- Expansion increases room/kitchen/storage area at a property-dependent cost.

Avoid a single “beauty score.” Show capacity, flow, condition, and appeal by segment so different layouts remain viable.

## UI and camera

Add an Edit Interior mode to the current viewer:

- Catalog organized by seating, kitchen, service, decoration, entertainment, finishes, and utilities.
- Ghost placement, grid/surface snapping, rotate controls, undo/redo, bulldoze/sell, and repair.
- Live evaluation panel for seats, kitchen throughput, queue space, path warnings, style, segment appeal, and budget.
- Heatmaps for congestion, staff walking distance, cleanliness, and customer sentiment.
- “Interior designer” templates as a later headquarters/manager unlock, with preview and price before applying.

Pause the local interior simulation while editing, but do not silently pause the whole world unless the player chooses to.

## Integration requirements

- `RestaurantState.table_count` and cook capacity derive from layout evaluation.
- Operations snapshots reference real furniture anchors.
- Demand uses atmosphere, condition, and segment appeal.
- Economy records purchases, resale, repair, maintenance, and expansion.
- Staff pathing uses layout navigation and reports congestion.
- Awards inspect layout quality and style.
- Sabotage can damage specific objects; managers can repair according to policy.
- Save data stores layout state and safely replaces missing furniture definitions with placeholders/refunds.

## Delivery phases

### Phase 1 — Layout state and read-only evaluation

Represent the current fixed interior as generated placed furniture. Derive seats and cook stations from the layout while preserving existing behavior.

### Phase 2 — Placement MVP

Ship tables, chairs, ovens, counters, move/rotate/sell, collision checks, save/load, and undo/redo.

### Phase 3 — Appeal and condition

Add styles, demographic preferences, finishes, decorations, music, durability, repair, and cleanliness.

### Phase 4 — Flow, expansion, and automation

Add congestion heatmaps, room expansion, designer templates, manager repair policies, richer assets, and AI layout selection.

## Acceptance criteria

- The player can build a valid restaurant from an empty permitted layout and observe customers use it.
- Removing a table or oven immediately and correctly changes capacity after commit.
- Invalid placements cannot block the only entrance or make required stations unreachable.
- Two layouts with equal furniture value but different flow produce different service throughput.
- Segment appeal responds to style, comfort, music, crowding, and condition.
- Layouts persist exactly across save/load and remain recoverable when content definitions change.
- AI can choose and apply valid templates within budget.

## Risks and controls

- **Pathfinding instability:** separate preview validation from batched navigation rebuilds and maintain known-safe fallback layouts.
- **Asset scale mismatch:** validate furniture metadata and interaction anchors in automated content audits.
- **Micromanagement overload:** templates, multi-select, copy/paste between branches, and manager automation.
- **Simulation coupling:** keep operational state keyed by stable furniture IDs so visual rebuilds do not lose orders or actors.

