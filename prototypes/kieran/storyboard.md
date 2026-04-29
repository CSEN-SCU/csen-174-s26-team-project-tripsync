# Orbit storyboard — Kieran product narrative

Six-frame story for **Orbit as a real product**, told through **one** named traveler. **Friends appear only as “the group”**—no separate named characters—while the plot still needs **shared and clashing interests** so everyone’s must-hits can land on **one itinerary**, and **passive mode** covers **solo** time without a second app.

*(Beats align with **`prototypes/kieran`**—friends, synced itinerary / wishlist, interests, map + nearby POIs, passive heads-up, voice snippets, bottom-bar follow-up.)*

---

## Persona (single main character)

**Riley** — **20**, **sophomore** at **Santa Clara University**, **photography hobbyist** who prefers **long bike loops** and **stopping wherever the light looks wrong in a good way**. Often joins **a few dorm friends** on **cheap weekend trips**; the group overlaps on “get out of town” but rarely agrees on **pace** or **what counts as a stop** (food vs. galleries vs. trails). Riley is fine with **everyday tech**—maps, group chat, voice memos—but on the road wants to **look up**, not **moderate a spreadsheet**. **One anchor day** per trip (the ride or the big outing) is non-negotiable; everything else can stay **loose**—as long as nobody’s wishes disappear.

---

## Generated 6-frame storyline

### Frame 1: Introducing the main character

Riley loads the car for a **short coastal weekend** with the usual crowd. The **anchor** is clear in Riley’s head: **one long ride along a set route**. The **around it** is mushy—**someone** always cares about **museums**, **someone** about **where to eat**, **someone** about **wandering old blocks**—and Riley keeps ending up as the person who says, “**Send me that pin again?**” Riley wants the trip to feel **shared**, not like unpaid project management.

### Frame 2: The problem emerges

The group chat does what it always does: **parallel drafts**—screenshots, half-finished lists, **timed tickets** that don’t line up with **“we’ll grab lunch whenever.”** **Shared** excitement (everyone wants **one good view**) gets buried under **conflicting** ones (**sun vs. shade**, **fixed slot vs. go-with-the-flow**). Riley sits at a gas pump, thumb sore, **half-listening** to laughter inside the car. *The trip is supposed to be for **people**, not for **inboxes**.*

### Frame 3: The “oh crap” moment

They burn a **chunk of morning** standing in the wrong kind of line: the **group** thought a **museum block** was locked; Riley thought that window was **flex** for a **walking loop** someone else had pushed for; **meanwhile nobody aligned lunch** with either. Riley feels the familiar sink: **nobody meant harm**, but **every “must” lived in a different app**, so fairness never had a **single surface** to land on. Riley had also hoped for **twenty quiet minutes alone** before the day spun up—already gone to damage control.

### Frame 4: The solution appears

Riley convinces the group to try **Orbit**: **connect as friends**, **build one shared itinerary** on one map—**stops, rough windows, optional pins**, interests dialed so **clashes become order** instead of vibes in four apps. Riley’s **anchor ride** stays visible so it doesn’t get negotiated away by accident. For the moments Riley wants **off the group clock**—dawn pedal, solo wander while others sleep—Riley flips **passive mode**: **one heads-up per place** when crossing a ring, **no need to rehearse the day** on a screen first.

### Frame 5: The “aha” moment

**With the group**, the day **finally moves** on **one line**: timed stops show up where they belong; food lands **before** hangry; the **history walk** becomes a **bridge between** two real pins instead of a guilt detour. At a corner everyone bookmarked, a **short voice line** plays while the building is still in view; **the group** hears the same beat; **a follow-up** in the bottom bar stays **about that sidewalk**, not a random article link.

**Alone**, Riley slips out early with **passive on**—no performance, no “where’s Riley?” panic—just **cool air**, tires humming, and **one calm cue** near an **optional** trail note the shared list had held for “if energy allows.” Riley **asks one question**, **listens**, keeps pedaling. *Showing up for **friends’** wishes didn’t cost Riley **curiosity** on solo time.*

### Frame 6: Life after Orbit

Riley still picks the **anchor** first—that habit won’t die—but **group weekends stop feeling zero-sum**. **Conflicting interests** show up as **sequence on one map**, not as who lost the argument. Back at SCU, Riley still toggles **passive** for **solo** laps between classes: **present**, not curating a trip for an audience. Friends already have a dumb nickname for the app: **“the one map we don’t fight over.”** Riley didn’t pick the name—but **Riley’s** the one who finally got to **look up**.

---

## Visual style

- **Fat-marker / sharpie** sketches, **minimal monochrome**.
- Optional **spot color**: Riley’s bike or camera strap; itinerary stops tagged by **interest type** (food / history / trail), **not** by person’s name.

### Per-frame visual notes

| Frame | Visual | Mood |
|-------|--------|------|
| 1 | Riley at open car door, bike on rack; blurred figures in background (no faces required) | Excited, slightly responsible |
| 2 | Riley lit by phone chaos; car interior soft behind | Tense, loving-but-messy |
| 3 | Riley’s expression; clock; anonymous hands pointing different directions | Regret, urgency |
| 4 | Riley’s hands on one phone: **shared itinerary** + **passive** toggle | Relief, clarity |
| 5 | **Split:** group at one doorway (silhouettes); **Riley solo** on bike, earbuds, subtle ring | Joy + peace |
| 6 | Riley alone on campus path; distant suggestion of a car or group as tiny background, not characters | Grounded, belonging |

---

## Storyboard quality check

| Question | Answer |
|----------|--------|
| **Is the main character relatable?** | Yes — SCU student, anchor day + spontaneity, doesn’t want to run the trip from a phone. |
| **Is the problem visceral?** | Yes — competing threads; fairness has no single home; presence slips. |
| **Is the “oh crap” moment real?** | Yes — misaligned musts; solo buffer lost to chaos. |
| **Is the solution introduction natural?** | Yes — one shared itinerary + passive for Riley alone. |
| **Is the “aha” moment believable?** | Yes — group on one line + voice; solo passive without theater. |
| **Is the “after” state aspirational?** | Yes — fair group trips; Riley keeps solo curiosity. |

---

## Feature mapping (Kieran implementation)

| Story beat | Build |
|------------|--------|
| Friends + one plan | Friends APIs; debounced **wishlist / itinerary** sync (`README.md`) |
| Interests (overlap vs. clash) | **Filters** / interest hooks shaping narration and POI emphasis |
| Map + nearby POIs | `POST /api/nearby` (Overpass); tourism, historic, museums, parks, natural |
| Group day on foot | Shared stops + voice + bottom-dock **next** / **replay** / follow-up |
| Solo / presence | **Passive mode** — one-time radius heads-up |
| Motion-aware surfacing | GPS + heading / speed for what’s **ahead** |
| Rich blurbs | Wikipedia / Wikidata-backed short text when available |

This file lives under **`prototypes/kieran/`** next to the runnable stack in **`README.md`**.
