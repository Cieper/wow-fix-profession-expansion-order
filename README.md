# Fix Profession Expansion Order

Fixes the newest expansion showing up below the previous one in the profession recipe search list.

## The problem

Recipe search results are grouped by expansion, sorted by each category's `uiOrder`. The two newest expansions currently share the same `uiOrder` (900), so Blizzard's sort falls through to its tiebreaker — a plain alphabetical name compare — which puts "Khaz Algar" above "Midnight" even though Midnight is the newer expansion.

## The fix

The `uiOrder` values themselves can't be changed, but the sort that uses them is plain Lua, so this addon overrides the root category comparator: when `uiOrder` ties, it breaks the tie by category ID descending instead of alphabetically. Newer content always has a higher category ID, so the newer expansion wins the tie. Every other expansion, which already has a distinct `uiOrder`, is left exactly where Blizzard puts it. The sort is applied before the list renders (not after), so it's correct on the very first paint instead of jumping into place a frame later. Both the Recipes tab and the Crafting Orders browse tab get patched, since they share the same list and sort.

## Usage

- `/fpeo` or `/expansionorder` — print every root category with its `uiOrder`, flagging any that collide, so you can confirm the fix is doing the right thing on your client.

## Compatibility

Targets WoW: Midnight (`## Interface: 120100`).

## License

MIT, see [LICENSE](LICENSE).
