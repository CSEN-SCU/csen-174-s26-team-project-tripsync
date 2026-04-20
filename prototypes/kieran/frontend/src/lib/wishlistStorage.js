function keysForUser(userId) {
  if (userId == null || !Number.isFinite(Number(userId))) {
    return { groups: null, items: null };
  }
  const id = String(userId);
  return {
    groups: `orbit_kieran_wishlist_groups_v1_u${id}`,
    items: `orbit_kieran_wishlist_items_v1_u${id}`,
  };
}

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

/**
 * Load itineraries for a signed-in user. Each user has separate localStorage keys.
 * @param {number|null|undefined} userId
 */
export function loadWishlist(userId) {
  if (userId == null || !Number.isFinite(Number(userId))) {
    return { groups: defaultWishlistGroups(), items: [] };
  }
  const k = keysForUser(userId);
  try {
    const rawG = localStorage.getItem(k.groups);
    const rawI = localStorage.getItem(k.items);
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

/**
 * Persist itineraries for the current user only.
 * @param {number|null|undefined} userId
 */
export function saveWishlist(userId, groups, items) {
  if (userId == null || !Number.isFinite(Number(userId))) return;
  const k = keysForUser(userId);
  try {
    localStorage.setItem(k.groups, JSON.stringify(groups));
    localStorage.setItem(k.items, JSON.stringify(items));
  } catch {
    /* private mode etc. */
  }
}

export function newWishlistId() {
  return `w-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}
