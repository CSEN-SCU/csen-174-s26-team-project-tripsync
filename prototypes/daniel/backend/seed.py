"""Seed the database with POIs along the SCU-to-Joshua Tree corridor."""

from database import engine, SessionLocal, Base
from models import POI, UserPreference

POIS = [
    # ── Santa Clara / San Jose ──────────────────────────────────────
    {
        "name": "Winchester Mystery House",
        "lat": 37.3184,
        "lng": -121.9511,
        "category": "historic",
        "short_description": "A sprawling Victorian mansion built continuously for 38 years by the widow of the Winchester rifle fortune, featuring stairs to nowhere and doors that open to walls.",
        "tags": "history,architecture,quirky,haunted",
    },
    {
        "name": "Rosicrucian Egyptian Museum",
        "lat": 37.3425,
        "lng": -121.9148,
        "category": "historic",
        "short_description": "The largest collection of Egyptian artifacts on the West Coast, housed in a building modeled after an ancient Egyptian temple — right in the middle of San Jose.",
        "tags": "history,museum,architecture,hidden-gem",
    },
    {
        "name": "Psycho Donuts",
        "lat": 37.3217,
        "lng": -121.9290,
        "category": "food",
        "short_description": "An asylum-themed donut shop serving wild creations like the 'Cereal Killer' and 'Dead Elvis.' The interior looks like a mad scientist's lab.",
        "tags": "food,quirky,dessert,local",
    },

    # ── Gilroy / Pacheco Pass ───────────────────────────────────────
    {
        "name": "Gilroy Garlic Farm",
        "lat": 36.9933,
        "lng": -121.5528,
        "category": "food",
        "short_description": "The garlic capital of the world. This family farm sells everything from garlic ice cream to garlic braids.",
        "tags": "food,farm,quirky,local",
    },
    {
        "name": "Casa de Fruta",
        "lat": 36.8578,
        "lng": -121.4042,
        "category": "roadside",
        "short_description": "A sprawling roadside attraction that started as a cherry stand in 1943 and grew into a complex with a carousel, train, wine tasting, and a peacock park.",
        "tags": "roadside,food,family,quirky",
    },

    # ── Central Valley / I-5 South ──────────────────────────────────
    {
        "name": "Coalinga Horned Toad Derby Grounds",
        "lat": 36.1397,
        "lng": -120.3600,
        "category": "quirky",
        "short_description": "Coalinga hosts an annual Horned Toad Derby where participants race horned lizards. The tradition dates back to 1934.",
        "tags": "quirky,roadside,history,wildlife",
    },
    {
        "name": "Colonel Allensworth State Historic Park",
        "lat": 35.8644,
        "lng": -119.3870,
        "category": "historic",
        "short_description": "The only California town founded, financed, and governed entirely by African Americans. Established in 1908 by a formerly enslaved person who became the highest-ranking Black officer of his time.",
        "tags": "history,park,civil-rights,hidden-gem",
    },

    # ── Tehachapi / Mountain Pass ───────────────────────────────────
    {
        "name": "Tehachapi Loop",
        "lat": 35.1319,
        "lng": -118.5275,
        "category": "landmark",
        "short_description": "A famous engineering marvel where the railroad track spirals over itself so long trains cross above their own tail. Built in 1876, still active.",
        "tags": "engineering,trains,landmark,photography",
    },
    {
        "name": "Tehachapi Wind Farm",
        "lat": 35.0786,
        "lng": -118.4370,
        "category": "landmark",
        "short_description": "One of the first large-scale wind farms in the world, with nearly 5,000 turbines. Driving through feels like entering a sci-fi landscape.",
        "tags": "energy,landmark,photography,engineering",
    },

    # ── Mojave Desert ───────────────────────────────────────────────
    {
        "name": "Mojave Air & Space Port",
        "lat": 35.0594,
        "lng": -118.1519,
        "category": "historic",
        "short_description": "The first FAA-licensed spaceport in the US. SpaceShipOne launched from here. Rows of retired jets being scrapped are visible from the road.",
        "tags": "aviation,space,engineering,photography",
    },
    {
        "name": "Exotic Feline Breeding Compound",
        "lat": 35.0478,
        "lng": -117.8250,
        "category": "wildlife",
        "short_description": "A small rescue and breeding facility housing rare wildcats including fishing cats, jungle cats, and Pallas's cats. Open by appointment.",
        "tags": "wildlife,animals,hidden-gem,conservation",
    },

    # ── Barstow / Route 66 ──────────────────────────────────────────
    {
        "name": "Elmer's Bottle Tree Ranch",
        "lat": 34.8480,
        "lng": -117.0830,
        "category": "roadside",
        "short_description": "Over 200 'trees' made from welded pipes and glass bottles line this stretch of old Route 66. Free to visit, open 24/7.",
        "tags": "art,roadside,route-66,photography,quirky",
    },
    {
        "name": "Peggy Sue's 50's Diner",
        "lat": 34.9378,
        "lng": -116.9553,
        "category": "food",
        "short_description": "A classic 1950s-themed diner in the middle of the Mojave Desert, complete with a dinosaur park next door. Famous for milkshakes and Route 66 vibes.",
        "tags": "food,retro,route-66,quirky,diner",
    },
    {
        "name": "Rainbow Basin Natural Area",
        "lat": 35.0206,
        "lng": -116.9958,
        "category": "nature",
        "short_description": "Folded, multi-colored rock formations that look like a rainbow frozen in stone. Fossils of ancient camels and saber-toothed cats have been found here.",
        "tags": "geology,nature,hiking,photography,fossils",
    },

    # ── Landers / Giant Rock area ───────────────────────────────────
    {
        "name": "Integratron",
        "lat": 34.2928,
        "lng": -116.3886,
        "category": "quirky",
        "short_description": "A dome built by a UFO contactee in the 1950s on a geomagnetic vortex. Today it hosts 'sound baths' where quartz bowls resonate around you.",
        "tags": "quirky,spiritual,sound,hidden-gem,ufo",
    },
    {
        "name": "Giant Rock",
        "lat": 34.3312,
        "lng": -116.3872,
        "category": "landmark",
        "short_description": "The largest freestanding boulder in the world — seven stories tall. In the 1950s, UFO conventions were held here.",
        "tags": "geology,ufo,history,landmark,desert",
    },

    # ── Pioneertown (just outside JT) ───────────────────────────────
    {
        "name": "Pappy & Harriet's Pioneertown Palace",
        "lat": 34.1578,
        "lng": -116.4947,
        "category": "food",
        "short_description": "A legendary honky-tonk in a fake Wild West town built as a 1940s movie set. Paul McCartney and Robert Plant have played surprise shows here.",
        "tags": "food,music,nightlife,hidden-gem,historic",
    },
    {
        "name": "Pioneertown",
        "lat": 34.1573,
        "lng": -116.4972,
        "category": "historic",
        "short_description": "A Wild West movie set built in 1946 by Roy Rogers and Gene Autry. The 'Mane Street' was designed to look authentic from every camera angle.",
        "tags": "history,film,architecture,western,photography",
    },

    # ══════════════════════════════════════════════════════════════════
    # ── Joshua Tree Town — DENSE WALKABLE CLUSTER ────────────────────
    # These are spaced ~0.1–0.3 km apart along Park Blvd / Twentynine
    # Palms Hwy so testers can drag short distances and hit new POIs.
    # ══════════════════════════════════════════════════════════════════
    {
        "name": "World Famous Crochet Museum",
        "lat": 34.1356,
        "lng": -116.3131,
        "category": "quirky",
        "short_description": "The world's smallest museum — a converted photo booth stuffed with crocheted animals, aliens, and pop culture figures. Free admission.",
        "tags": "quirky,art,free,museum,hidden-gem",
    },
    {
        "name": "Joshua Tree Saloon",
        "lat": 34.1345,
        "lng": -116.3131,
        "category": "food",
        "short_description": "A beloved local dive bar covered in stickers and dollar bills. The burgers are massive, the crowd is friendly, and there's live music on weekends.",
        "tags": "food,nightlife,local,music,dive-bar",
    },
    {
        "name": "Natural Sisters Café",
        "lat": 34.1350,
        "lng": -116.3115,
        "category": "food",
        "short_description": "A tiny café with fresh organic smoothies, acai bowls, and veggie wraps. The go-to fuel stop before heading into the park.",
        "tags": "food,healthy,organic,cafe,local",
    },
    {
        "name": "Joshua Tree Coffee Company",
        "lat": 34.1354,
        "lng": -116.3100,
        "category": "food",
        "short_description": "A small-batch coffee roaster in a cozy desert cabin. Their cold brew is locally famous and they have a shady patio perfect for morning hangs.",
        "tags": "food,coffee,local,cafe",
    },
    {
        "name": "JT Country Kitchen",
        "lat": 34.1348,
        "lng": -116.3085,
        "category": "food",
        "short_description": "Old-school breakfast diner where locals and climbers fuel up on huge plates of biscuits and gravy before dawn sends in the park.",
        "tags": "food,breakfast,local,diner",
    },
    {
        "name": "Ricochet Vintage & Thrift",
        "lat": 34.1352,
        "lng": -116.3070,
        "category": "quirky",
        "short_description": "A curated desert thrift shop packed with vintage cowboy boots, turquoise jewelry, vinyl records, and weird desert oddities.",
        "tags": "shopping,vintage,quirky,local",
    },
    {
        "name": "Joshua Tree Art Gallery",
        "lat": 34.1355,
        "lng": -116.3055,
        "category": "art",
        "short_description": "A community gallery featuring rotating exhibitions by desert artists — paintings, photography, ceramics, and mixed media all inspired by the landscape.",
        "tags": "art,gallery,local,desert,photography",
    },
    {
        "name": "Beatnik Lounge",
        "lat": 34.1349,
        "lng": -116.3040,
        "category": "food",
        "short_description": "An intimate live music venue and bar with an open-air patio. Local bands, desert rock, and open mic nights under the stars.",
        "tags": "music,nightlife,local,bar,live-music",
    },
    {
        "name": "Joshua Tree Outfitters",
        "lat": 34.1358,
        "lng": -116.3025,
        "category": "outdoor",
        "short_description": "A climbing and outdoor gear shop run by local climbers. They know every boulder problem in the park and give honest beta for free.",
        "tags": "climbing,gear,outdoor,local",
    },
    {
        "name": "Sam's Indian Food",
        "lat": 34.1342,
        "lng": -116.3010,
        "category": "food",
        "short_description": "Unexpectedly excellent Indian food in the middle of the desert. Their tikka masala and garlic naan are a revelation after a long day on the rocks.",
        "tags": "food,indian,local,hidden-gem",
    },
    {
        "name": "Joshua Tree Astronomy Arts Theater",
        "lat": 34.1360,
        "lng": -116.2990,
        "category": "art",
        "short_description": "A small community theater hosting desert film screenings, astronomy talks, and live performances. Check their chalkboard out front for tonight's show.",
        "tags": "art,theater,astronomy,local,community",
    },
    {
        "name": "Park Rock Café",
        "lat": 34.1344,
        "lng": -116.2975,
        "category": "food",
        "short_description": "A colorful roadside café with massive burritos, fresh-squeezed lemonade, and a sun-bleached patio. Popular with climbers comparing beta over lunch.",
        "tags": "food,cafe,climbing,local",
    },
    {
        "name": "High Desert Mural — 'Desert Bloom'",
        "lat": 34.1351,
        "lng": -116.2960,
        "category": "art",
        "short_description": "A vibrant 40-foot mural on the side of a building depicting blooming Joshua trees and desert wildflowers. A popular photo spot.",
        "tags": "art,mural,photography,street-art",
    },

    # ── Joshua Tree National Park ────────────────────────────────────
    {
        "name": "Joshua Tree Visitor Center",
        "lat": 34.0704,
        "lng": -116.1703,
        "category": "landmark",
        "short_description": "The main park entrance with ranger-led programs, trail maps, and a bookstore. Ask the rangers about the best sunset spots — they have favorites they don't put in the brochure.",
        "tags": "park,information,ranger,hiking",
    },
    {
        "name": "Hidden Valley",
        "lat": 34.0125,
        "lng": -116.1694,
        "category": "outdoor",
        "short_description": "A legendary bouldering destination surrounded by massive rock formations. Legend says cattle rustlers hid stolen herds here — only one narrow entrance.",
        "tags": "climbing,bouldering,hiking,nature,legend",
    },
    {
        "name": "Skull Rock",
        "lat": 33.9978,
        "lng": -116.0503,
        "category": "nature",
        "short_description": "A naturally weathered granite formation that looks exactly like a human skull. The hidden trail behind it through a boulder-strewn wash is the real gem.",
        "tags": "nature,geology,hiking,photography,park",
    },
    {
        "name": "Keys View",
        "lat": 33.9244,
        "lng": -116.1870,
        "category": "nature",
        "short_description": "A panoramic viewpoint overlooking the Coachella Valley, the San Andreas Fault, and the Salton Sea. On clear days you can see to Mexico.",
        "tags": "nature,views,photography,sunset,park",
    },
    {
        "name": "Cholla Cactus Garden",
        "lat": 33.9253,
        "lng": -115.9286,
        "category": "nature",
        "short_description": "A dense grove of teddy bear cholla cacti that glow golden in late afternoon light. Beautiful but don't touch — the barbed spines are nearly impossible to remove.",
        "tags": "nature,photography,desert,cactus,park",
    },
    {
        "name": "Arch Rock Trail",
        "lat": 33.9472,
        "lng": -115.9025,
        "category": "outdoor",
        "short_description": "A short trail leading to a stunning natural granite arch — one of the most impressive rock formations in Joshua Tree.",
        "tags": "hiking,climbing,photography,geology,nature",
    },
    {
        "name": "Ryan Mountain Trail",
        "lat": 33.9867,
        "lng": -116.1200,
        "category": "outdoor",
        "short_description": "A 3-mile round trip hike to one of the best panoramic views in the park. The summit gives a 360-degree view of the desert basin and surrounding mountains.",
        "tags": "hiking,views,nature,photography,park",
    },

    # ── Twentynine Palms ─────────────────────────────────────────────
    {
        "name": "Noah Purifoy Outdoor Desert Art Museum",
        "lat": 34.2447,
        "lng": -116.3164,
        "category": "art",
        "short_description": "Ten acres of large-scale sculptures built entirely from junk and found objects. Free, open dawn to dusk, no staff — just you and the art in the desert.",
        "tags": "art,sculpture,free,desert,hidden-gem",
    },
    {
        "name": "29 Palms Inn",
        "lat": 34.1367,
        "lng": -116.0547,
        "category": "food",
        "short_description": "A historic desert oasis inn built around a natural spring in 1928. The spring-fed pond is home to the endangered desert pupfish.",
        "tags": "food,history,oasis,wildlife,garden",
    },
    {
        "name": "Sky's The Limit Observatory",
        "lat": 34.1122,
        "lng": -116.0333,
        "category": "nature",
        "short_description": "A community-built observatory offering free public stargazing nights. Joshua Tree has some of the darkest skies near any major city.",
        "tags": "astronomy,stargazing,free,nature,night",
    },
]

DEFAULT_INTERESTS = [
    "climbing",
    "outdoors",
    "food",
    "history",
    "hidden gems",
]


def seed():
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        existing = db.query(POI).count()
        if existing != len(POIS):
            db.query(POI).delete()
            db.commit()
            for poi_data in POIS:
                db.add(POI(**poi_data))
            db.commit()
            print(f"Seeded {len(POIS)} POIs (replaced {existing} old records)")
        else:
            print(f"Database already has {existing} POIs, skipping seed")

        if db.query(UserPreference).count() == 0:
            for interest in DEFAULT_INTERESTS:
                db.add(UserPreference(interest=interest, active=1))
            db.commit()
            print(f"Seeded {len(DEFAULT_INTERESTS)} default interests")
    finally:
        db.close()


if __name__ == "__main__":
    seed()
