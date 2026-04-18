const LS_GROUPS = "orbit_kieran_wishlist_groups_v1";
const LS_ITEMS = "orbit_kieran_wishlist_items_v1";

export const GROUP_COLOR_PALETTE = [
  "#e879f9",
  "#22d3ee",
  "#a3e635",
  "#fb923c",
  "#818cf8",
  "#f472b6",
  "#fbbf24",
  "#2dd4bf",
];

export function defaultWishlistGroups() {
  return [{ id: "g-default", name: "My plans", color: GROUP_COLOR_PALETTE[0] }];
}

export function loadWishlist() {
  try {
    const rawG = localStorage.getItem(LS_GROUPS);
    const rawI = localStorage.getItem(LS_ITEMS);
    const groups = rawG ? JSON.parse(rawG) : null;
    const items = rawI ? JSON.parse(rawI) : null;
    return {
      groups:
        Array.isArray(groups) && groups.length > 0
          ? groups
          : defaultWishlistGroups(),
      items: Array.isArray(items) ? items : [],
    };
  } catch {
    return { groups: defaultWishlistGroups(), items: [] };
  }
}

export function saveWishlist(groups, items) {
  try {
    localStorage.setItem(LS_GROUPS, JSON.stringify(groups));
    localStorage.setItem(LS_ITEMS, JSON.stringify(items));
  } catch {
    /* private mode etc. */
  }
}

export function newWishlistId() {
  return `w-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}
