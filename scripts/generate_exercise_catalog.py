#!/usr/bin/env python3
"""Generate JIMM/ExerciseCatalog.swift from structured exercise data."""

from __future__ import annotations

import re
from pathlib import Path

# (name, category, aliases, logging_type)
# logging_type: strength | bodyweight | cardio | duration | mobility
Exercise = tuple[str, str, list[str], str]


def e(name: str, cat: str, aliases: list[str] | None = None, lt: str = "strength") -> Exercise:
    return (name, cat, aliases or [], lt)


EXERCISES: list[Exercise] = []


def add(*items: Exercise) -> None:
    EXERCISES.extend(items)


# ─── Chest ───────────────────────────────────────────────────────────────────
add(
    e("Barbell Bench Press", "Chest", ["bench press", "flat bench", "bb bench", "bench"]),
    e("Dumbbell Bench Press", "Chest", ["db bench", "flat dumbbell press", "dumbbell press"]),
    e("Smith Machine Bench Press", "Chest", ["smith bench"]),
    e("Machine Chest Press", "Chest", ["chest press machine", "chest press"]),
    e("Incline Barbell Bench Press", "Chest", ["incline bench", "incline bench press", "incline bb press"]),
    e("Incline Dumbbell Press", "Chest", ["incline db press", "incline dumbbell press"]),
    e("Incline Machine Press", "Chest", ["incline chest machine", "incline chest press"]),
    e("Decline Barbell Bench Press", "Chest", ["decline bench", "decline bench press"]),
    e("Decline Dumbbell Press", "Chest", ["decline db press"]),
    e("Dumbbell Fly", "Chest", ["db fly", "flat fly", "chest fly"]),
    e("Incline Dumbbell Fly", "Chest", ["incline fly", "incline db fly"]),
    e("Cable Fly", "Chest", ["cable crossover", "crossover", "standing cable fly"]),
    e("High-to-Low Cable Fly", "Chest", ["high low cable fly"]),
    e("Low-to-High Cable Fly", "Chest", ["low high cable fly"]),
    e("Pec Deck Fly", "Chest", ["pec deck", "machine fly", "seated fly machine"]),
    e("Push-Up", "Chest", ["push up", "pushup", "push-ups"], "bodyweight"),
    e("Wide Push-Up", "Chest", ["wide grip push up", "wide pushup"], "bodyweight"),
    e("Diamond Push-Up", "Chest", ["close grip push up", "diamond pushup"], "bodyweight"),
    e("Decline Push-Up", "Chest", ["feet elevated push up"], "bodyweight"),
    e("Incline Push-Up", "Chest", ["hands elevated push up"], "bodyweight"),
    e("Chest Dip", "Chest", ["forward lean dip", "dip", "dips", "chest dips"], "bodyweight"),
    e("Weighted Dip", "Chest", ["weighted chest dip", "loaded dip"]),
    e("Landmine Chest Press", "Chest", ["landmine press"]),
    e("Floor Press", "Chest", ["barbell floor press"]),
    e("Dumbbell Floor Press", "Chest", ["db floor press"]),
    e("Pullover", "Chest", ["dumbbell pullover", "db pullover"]),
    e("Cable Pullover", "Chest", ["straight arm cable pullover"]),
    e("Squeeze Press", "Chest", ["dumbbell squeeze press"]),
    e("Neutral-Grip Dumbbell Press", "Chest", ["hammer grip db press"]),
    e("Resistance Band Chest Press", "Chest", ["band chest press"]),
)

# ─── Back ────────────────────────────────────────────────────────────────────
add(
    e("Pull-Up", "Back", ["pull up", "pullup", "pull-ups"], "bodyweight"),
    e("Chin-Up", "Back", ["chin up", "chinup", "chin-ups"], "bodyweight"),
    e("Neutral-Grip Pull-Up", "Back", ["parallel pull up", "neutral pull up"], "bodyweight"),
    e("Wide-Grip Pull-Up", "Back", ["wide pull up"], "bodyweight"),
    e("Weighted Pull-Up", "Back", ["loaded pull up"]),
    e("Assisted Pull-Up", "Back", ["band assisted pull up", "assisted chin up"], "bodyweight"),
    e("Lat Pulldown", "Back", ["lat pull down", "pulldown", "pull-down", "pull down"]),
    e("Wide-Grip Lat Pulldown", "Back", ["wide pulldown", "wide grip pulldown"]),
    e("Close-Grip Lat Pulldown", "Back", ["close pulldown", "close grip pulldown"]),
    e("Neutral-Grip Lat Pulldown", "Back", ["v-bar pulldown", "neutral pulldown"]),
    e("Reverse-Grip Lat Pulldown", "Back", ["underhand lat pulldown", "reverse pulldown"]),
    e("Straight-Arm Pulldown", "Back", ["lat prayer", "straight arm pull-down"]),
    e("Seated Cable Row", "Back", ["cable row", "seated row"]),
    e("Wide-Grip Seated Row", "Back", ["wide cable row"]),
    e("Close-Grip Seated Row", "Back", ["close cable row"]),
    e("Single-Arm Cable Row", "Back", ["one arm cable row"]),
    e("Chest-Supported Row", "Back", ["incline bench row", "chest supported row"]),
    e("Barbell Row", "Back", ["bent over row", "bb row", "bent-over row"]),
    e("Underhand Barbell Row", "Back", ["reverse grip row", "yates row"]),
    e("T-Bar Row", "Back", ["tbar row", "landmine row"]),
    e("Machine Row", "Back", ["plate loaded row", "seated machine row"]),
    e("Single-Arm Dumbbell Row", "Back", ["one arm row", "db row", "dumbbell row"]),
    e("Chest-Supported Dumbbell Row", "Back", ["incline db row"]),
    e("Chest-Supported Machine Row", "Back", ["machine supported row"]),
    e("Inverted Row", "Back", ["bodyweight row", "australian pull up"], "bodyweight"),
    e("Landmine Row", "Back", ["landmine single arm row", "meadows row"]),
    e("Renegade Row", "Back", ["db renegade row"]),
    e("Back Extension", "Back", ["hyperextension", "back raise"]),
    e("45-Degree Back Extension", "Back", ["45 degree hyper"]),
    e("Reverse Hyperextension", "Back", ["reverse hyper"]),
    e("Shrug", "Back", ["barbell shrug", "bb shrug"]),
    e("Dumbbell Shrug", "Back", ["db shrug"]),
    e("Trap Bar Shrug", "Back", ["hex bar shrug"]),
    e("Machine Shrug", "Back", ["shrug machine"]),
    e("Cable Shrug", "Back", ["cable shrugging"]),
    e("Smith Machine Row", "Back", ["smith row"]),
    e("Resistance Band Row", "Back", ["band row"]),
    e("Scapular Pull-Up", "Back", ["scap pull up"], "bodyweight"),
)

# ─── Shoulders ───────────────────────────────────────────────────────────────
add(
    e("Barbell Overhead Press", "Shoulders", ["overhead press", "ohp", "military press", "bb press", "strict press"]),
    e("Seated Barbell Overhead Press", "Shoulders", ["seated ohp", "seated military press"]),
    e("Push Press", "Shoulders", ["barbell push press"]),
    e("Dumbbell Shoulder Press", "Shoulders", ["db shoulder press", "dumbbell press", "shoulder press"]),
    e("Seated Dumbbell Shoulder Press", "Shoulders", ["seated db press", "seated shoulder press"]),
    e("Standing Dumbbell Shoulder Press", "Shoulders", ["standing db press"]),
    e("Arnold Press", "Shoulders", ["arnold dumbbell press"]),
    e("Machine Shoulder Press", "Shoulders", ["shoulder press machine"]),
    e("Smith Machine Overhead Press", "Shoulders", ["smith ohp", "smith shoulder press"]),
    e("Landmine Shoulder Press", "Shoulders", ["landmine press upright"]),
    e("Single-Arm Landmine Shoulder Press", "Shoulders", ["one arm landmine press"]),
    e("Kettlebell Press", "Shoulders", ["kb press"]),
    e("Dumbbell Lateral Raise", "Shoulders", ["lateral raise", "lat raise", "side raise", "side lateral raise", "db lateral raise"]),
    e("Cable Lateral Raise", "Shoulders", ["cable side raise"]),
    e("Machine Lateral Raise", "Shoulders", ["lateral raise machine"]),
    e("Single-Arm Cable Lateral Raise", "Shoulders", ["one arm cable lateral"]),
    e("Dumbbell Front Raise", "Shoulders", ["front raise", "db front raise"]),
    e("Cable Front Raise", "Shoulders", ["cable front raise"]),
    e("Plate Front Raise", "Shoulders", ["plate raise"]),
    e("Rear Delt Fly", "Shoulders", ["rear delt raise", "rear deltoid fly"]),
    e("Reverse Pec Deck", "Shoulders", ["reverse fly machine", "rear delt machine"]),
    e("Bent-Over Rear Delt Raise", "Shoulders", ["bent over lateral raise"]),
    e("Cable Rear Delt Fly", "Shoulders", ["cable rear delt"]),
    e("Face Pull", "Shoulders", ["facepull", "face-pull", "face pull", "cable face pull"]),
    e("Upright Row", "Shoulders", ["barbell upright row"]),
    e("Dumbbell Upright Row", "Shoulders", ["db upright row"]),
    e("Cable Upright Row", "Shoulders", ["cable upright"]),
    e("Y Raise", "Shoulders", ["dumbbell y raise"]),
    e("Band Pull-Apart", "Shoulders", ["pull apart", "band pull apart"]),
    e("Resistance Band Lateral Raise", "Shoulders", ["band lateral raise"]),
    e("Resistance Band Overhead Press", "Shoulders", ["band ohp"]),
    e("Pike Push-Up", "Shoulders", ["pike pushup"], "bodyweight"),
    e("Handstand Push-Up", "Shoulders", ["hspu", "handstand pushup"], "bodyweight"),
)

# ─── Arms ────────────────────────────────────────────────────────────────────
add(
    # Biceps
    e("Barbell Curl", "Arms", ["bb curl", "standing barbell curl"]),
    e("EZ-Bar Curl", "Arms", ["ez curl", "ez bar curl"]),
    e("Dumbbell Curl", "Arms", ["db curl", "bicep curl", "biceps curl"]),
    e("Alternating Dumbbell Curl", "Arms", ["alternating curl"]),
    e("Incline Dumbbell Curl", "Arms", ["incline curl"]),
    e("Seated Dumbbell Curl", "Arms", ["seated curl"]),
    e("Concentration Curl", "Arms", ["concentrated curl"]),
    e("Preacher Curl", "Arms", ["bb preacher curl", "ez preacher curl"]),
    e("Machine Preacher Curl", "Arms", ["preacher machine"]),
    e("Spider Curl", "Arms", ["incline spider curl"]),
    e("Cable Curl", "Arms", ["cable bicep curl"]),
    e("Hammer Curl", "Arms", ["db hammer curl", "neutral curl"]),
    e("Cross-Body Hammer Curl", "Arms", ["cross body hammer"]),
    e("Rope Hammer Curl", "Arms", ["cable hammer curl"]),
    e("Reverse Curl", "Arms", ["overhand curl"]),
    e("Machine Curl", "Arms", ["bicep machine"]),
    e("Single-Arm Cable Curl", "Arms", ["one arm cable curl"]),
    e("Resistance Band Curl", "Arms", ["band curl"]),
    e("Wrist Curl", "Arms", ["forearm curl", "wrist curls"]),
    e("Reverse Wrist Curl", "Arms", ["wrist extension"]),
    # Triceps
    e("Close-Grip Bench Press", "Arms", ["cgbp", "close grip bench"]),
    e("Skull Crusher", "Arms", ["lying triceps extension", "skullcrusher"]),
    e("EZ-Bar Skull Crusher", "Arms", ["ez skull crusher"]),
    e("Dumbbell Skull Crusher", "Arms", ["db skull crusher"]),
    e("Barbell Overhead Triceps Extension", "Arms", ["bb overhead extension", "french press"]),
    e("Seated Dumbbell Overhead Triceps Extension", "Arms", ["db overhead extension", "overhead triceps extension"]),
    e("Single-Arm Dumbbell Overhead Triceps Extension", "Arms", ["one arm overhead extension"]),
    e("Cable Triceps Pushdown", "Arms", ["triceps pushdown", "pushdown", "pressdown", "tricep pushdown"]),
    e("Rope Triceps Pushdown", "Arms", ["rope pushdown", "rope pressdown"]),
    e("Straight Bar Triceps Pushdown", "Arms", ["bar pushdown"]),
    e("V-Bar Triceps Pushdown", "Arms", ["v bar pushdown"]),
    e("Reverse Grip Triceps Pushdown", "Arms", ["underhand pushdown"]),
    e("Single-Arm Cable Triceps Pushdown", "Arms", ["one arm pushdown"]),
    e("Cable Overhead Triceps Extension", "Arms", ["cable overhead extension"]),
    e("Rope Overhead Triceps Extension", "Arms", ["rope overhead extension"]),
    e("Bench Dip", "Arms", ["bench dips"], "bodyweight"),
    e("Parallel Bar Dip", "Arms", ["triceps dip", "dip station"], "bodyweight"),
    e("Assisted Triceps Dip", "Arms", ["assisted dip"], "bodyweight"),
    e("Kickback", "Arms", ["triceps kickback", "db kickback"]),
    e("Cable Triceps Kickback", "Arms", ["cable kickback"]),
    e("Machine Triceps Extension", "Arms", ["triceps machine"]),
    e("Resistance Band Pushdown", "Arms", ["band pushdown"]),
    e("Resistance Band Overhead Extension", "Arms", ["band overhead extension"]),
)

# ─── Legs ────────────────────────────────────────────────────────────────────
add(
    e("Back Squat", "Legs", ["squat", "barbell squat", "bb squat", "high bar squat", "low bar squat"]),
    e("Front Squat", "Legs", ["barbell front squat"]),
    e("Goblet Squat", "Legs", ["dumbbell goblet squat", "kb goblet squat"]),
    e("Hack Squat", "Legs", ["hack squat machine"]),
    e("Safety Bar Squat", "Legs", ["ssb squat"]),
    e("Box Squat", "Legs", ["box squats"]),
    e("Smith Machine Squat", "Legs", ["smith squat"]),
    e("Leg Press", "Legs", ["leg press machine"]),
    e("Single-Leg Press", "Legs", ["one leg press"]),
    e("Bulgarian Split Squat", "Legs", ["rear foot elevated split squat", "rfess"]),
    e("Split Squat", "Legs", ["stationary lunge"]),
    e("Walking Lunge", "Legs", ["lunges", "lunge", "walking lunges"]),
    e("Reverse Lunge", "Legs", ["backward lunge"]),
    e("Forward Lunge", "Legs", ["front lunge"]),
    e("Lateral Lunge", "Legs", ["side lunge"]),
    e("Curtsy Lunge", "Legs", ["curtsy lunges"]),
    e("Step-Up", "Legs", ["box step up", "step ups"]),
    e("Deadlift", "Legs", ["conventional deadlift", "dead lift", "barbell deadlift"]),
    e("Sumo Deadlift", "Legs", ["wide stance deadlift", "sumo dl"]),
    e("Trap Bar Deadlift", "Legs", ["hex bar deadlift", "trap bar dl"]),
    e("Romanian Deadlift", "Legs", ["rdl", "barbell rdl", "stiff leg deadlift"]),
    e("Single-Leg Romanian Deadlift", "Legs", ["single leg rdl", "sl rdl"]),
    e("Good Morning", "Legs", ["good mornings", "barbell good morning"]),
    e("Leg Extension", "Legs", ["quad extension", "leg extensions"]),
    e("Single-Leg Extension", "Legs", ["one leg extension"]),
    e("Lying Leg Curl", "Legs", ["hamstring curl", "prone leg curl", "leg curl"]),
    e("Seated Leg Curl", "Legs", ["seated hamstring curl"]),
    e("Standing Leg Curl", "Legs", ["standing hamstring curl"]),
    e("Nordic Curl", "Legs", ["nordic hamstring curl"]),
    e("Glute-Ham Raise", "Legs", ["ghr", "glute ham"]),
    e("Standing Calf Raise", "Legs", ["calf raise", "calf raises", "standing calves"]),
    e("Seated Calf Raise", "Legs", ["seated calves"]),
    e("Leg Press Calf Raise", "Legs", ["leg press calves"]),
    e("Donkey Calf Raise", "Legs", ["donkey calves"]),
    e("Smith Machine Calf Raise", "Legs", ["smith calves"]),
    e("Hip Adduction Machine", "Legs", ["adductor machine", "hip adduction"]),
    e("Heels-Elevated Squat", "Legs", ["heel elevated squat"]),
    e("Landmine Squat", "Legs", ["landmine goblet squat"]),
    e("Pistol Squat", "Legs", ["single leg squat"], "bodyweight"),
    e("Cossack Squat", "Legs", ["side squat"], "bodyweight"),
    e("Wall Sit", "Legs", ["wall squat"], "bodyweight"),
    e("Jump Squat", "Legs", ["squat jump"], "bodyweight"),
    e("Sissy Squat", "Legs", ["sissy squats"]),
)

# ─── Glutes ──────────────────────────────────────────────────────────────────
add(
    e("Barbell Hip Thrust", "Glutes", ["hip thrust", "bb hip thrust"]),
    e("Dumbbell Hip Thrust", "Glutes", ["db hip thrust"]),
    e("Machine Hip Thrust", "Glutes", ["glute drive", "glute drive machine", "hip thrust machine"]),
    e("Smith Machine Hip Thrust", "Glutes", ["smith hip thrust"]),
    e("Banded Hip Thrust", "Glutes", ["band hip thrust"]),
    e("Single-Leg Hip Thrust", "Glutes", ["single leg hip thrust"]),
    e("Glute Bridge", "Glutes", ["bridge", "glute bridges"]),
    e("Single-Leg Glute Bridge", "Glutes", ["single leg bridge"]),
    e("Frog Pump", "Glutes", ["frog pumps"]),
    e("Cable Glute Kickback", "Glutes", ["glute kickback", "cable kickback"]),
    e("Machine Glute Kickback", "Glutes", ["kickback machine"]),
    e("Donkey Kick", "Glutes", ["donkey kicks"], "bodyweight"),
    e("Fire Hydrant", "Glutes", ["fire hydrants"], "bodyweight"),
    e("Clamshell", "Glutes", ["clamshells", "side lying clamshell"], "bodyweight"),
    e("Seated Hip Abduction Machine", "Glutes", ["hip abduction", "abductor machine", "hip abduction machine"]),
    e("Cable Hip Abduction", "Glutes", ["standing hip abduction"]),
    e("Banded Lateral Walk", "Glutes", ["monster walk", "band side walk"]),
    e("Cable Pull-Through", "Glutes", ["pull through"]),
    e("Hip Extension Machine", "Glutes", ["glute extension machine"]),
    e("Step-Down", "Glutes", ["single leg step down"]),
)

# ─── Core ────────────────────────────────────────────────────────────────────
add(
    e("Plank", "Core", ["front plank", "planks"], "bodyweight"),
    e("Side Plank", "Core", ["side planks"], "bodyweight"),
    e("Copenhagen Plank", "Core", ["copenhagen side plank"], "bodyweight"),
    e("Dead Bug", "Core", ["deadbug"], "bodyweight"),
    e("Bird Dog", "Core", ["bird dogs"], "bodyweight"),
    e("Hollow Hold", "Core", ["hollow body hold"], "bodyweight"),
    e("Superman", "Core", ["supermans", "arch hold", "back swan"], "bodyweight"),
    e("Crunch", "Core", ["crunches", "ab crunch"], "bodyweight"),
    e("Sit-Up", "Core", ["sit up", "situps", "sit-ups"], "bodyweight"),
    e("Reverse Crunch", "Core", ["reverse crunches"], "bodyweight"),
    e("Bicycle Crunch", "Core", ["bicycle crunches"], "bodyweight"),
    e("Hanging Leg Raise", "Core", ["hanging leg raises", "hlr"], "bodyweight"),
    e("Hanging Knee Raise", "Core", ["hanging knee raises"], "bodyweight"),
    e("Captain Chair Leg Raise", "Core", ["captain chair", "vertical leg raise"], "bodyweight"),
    e("Cable Crunch", "Core", ["kneeling cable crunch"]),
    e("Machine Crunch", "Core", ["ab machine"]),
    e("Pallof Press", "Core", ["cable pallof press", "pallof", "anti rotation press"]),
    e("Russian Twist", "Core", ["russian twists"], "bodyweight"),
    e("Wood Chop", "Core", ["cable woodchop", "woodchop"]),
    e("Ab Wheel Rollout", "Core", ["ab wheel", "ab rollout", "wheel rollout"]),
    e("Mountain Climber", "Core", ["mountain climbers"], "bodyweight"),
    e("Leg Raise", "Core", ["lying leg raise", "leg raises"], "bodyweight"),
    e("Flutter Kick", "Core", ["flutter kicks"], "bodyweight"),
    e("V-Up", "Core", ["v ups", "jackknife"], "bodyweight"),
    e("Side Crunch", "Core", ["oblique crunch"], "bodyweight"),
    e("Oblique Cable Crunch", "Core", ["cable oblique crunch"]),
    e("Plank Up-Down", "Core", ["plank to push up"], "bodyweight"),
    e("Medicine Ball Slam", "Core", ["med ball slam", "ball slam"]),
    e("Landmine Rotation", "Core", ["landmine twist"]),
)

# ─── Cardio ──────────────────────────────────────────────────────────────────
add(
    e("Treadmill Walk", "Cardio", ["walking treadmill"], "cardio"),
    e("Treadmill Run", "Cardio", ["treadmill", "treadmill running"], "cardio"),
    e("Treadmill Incline Walk", "Cardio", ["incline walk"], "cardio"),
    e("Outdoor Walk", "Cardio", ["walking", "walk"], "cardio"),
    e("Outdoor Run", "Cardio", ["running", "run", "jog"], "cardio"),
    e("Outdoor Sprint", "Cardio", ["sprints", "sprint"], "cardio"),
    e("Stationary Bike", "Cardio", ["exercise bike", "bike", "cycling"], "cardio"),
    e("Spin Bike", "Cardio", ["spin class bike", "indoor cycle"], "cardio"),
    e("Assault Bike", "Cardio", ["air bike", "assaultbike", "fan bike", "echo bike"], "cardio"),
    e("Elliptical", "Cardio", ["elliptical trainer", "cross trainer"], "cardio"),
    e("Rowing Machine", "Cardio", ["rower", "erg", "concept2", "rowing"], "cardio"),
    e("Stair Climber", "Cardio", ["stairmaster", "stair master", "stepmill", "stairs"], "cardio"),
    e("Ski Erg", "Cardio", ["ski ergometer", "skierg"], "cardio"),
    e("Jump Rope", "Cardio", ["skipping", "rope jumping", "skip rope"], "cardio"),
    e("Battle Ropes", "Cardio", ["battle rope", "heavy ropes"], "cardio"),
    e("Swimming", "Cardio", ["swim", "pool swim"], "cardio"),
    e("Jumping Jack", "Cardio", ["jumping jacks"], "cardio"),
    e("High Knees", "Cardio", ["high knee run"], "cardio"),
    e("Box Step", "Cardio", ["step ups cardio", "stepper"], "cardio"),
    e("Hiking", "Cardio", ["hike", "trail hike"], "cardio"),
    e("Rucking", "Cardio", ["ruck walk", "weighted walk"], "cardio"),
    e("Shadow Boxing", "Cardio", ["shadowbox"], "cardio"),
    e("Rowing Intervals", "Cardio", ["row intervals", "erg intervals"], "cardio"),
    e("Cycling Intervals", "Cardio", ["bike intervals"], "cardio"),
)

# ─── Full Body ───────────────────────────────────────────────────────────────
add(
    e("Burpee", "Full Body", ["burpees"], "bodyweight"),
    e("Thruster", "Full Body", ["barbell thruster", "thrusters"]),
    e("Dumbbell Thruster", "Full Body", ["db thruster"]),
    e("Kettlebell Swing", "Full Body", ["kb swing", "russian kettlebell swing", "american kettlebell swing"]),
    e("Farmer Carry", "Full Body", ["farmers walk", "farmer walk", "farmers carry"], "duration"),
    e("Suitcase Carry", "Full Body", ["suitcase walk"], "duration"),
    e("Overhead Carry", "Full Body", ["oh carry"], "duration"),
    e("Turkish Get-Up", "Full Body", ["tgu", "get up"]),
    e("Clean and Press", "Full Body", ["clean & press", "dumbbell clean and press"]),
    e("Wall Ball", "Full Body", ["wall balls", "med ball wall ball"]),
    e("Sled Push", "Full Body", ["prowler push", "sled"]),
    e("Sled Pull", "Full Body", ["sled drag"]),
    e("Box Jump", "Full Body", ["box jumps"], "bodyweight"),
    e("Broad Jump", "Full Body", ["standing long jump"], "bodyweight"),
    e("Bear Crawl", "Full Body", ["bear crawls"], "bodyweight"),
    e("Medicine Ball Clean", "Full Body", ["med ball clean"]),
    e("Devil Press", "Full Body", ["db devil press"]),
    e("Man Maker", "Full Body", ["dumbbell man maker"]),
    e("Kettlebell Clean and Press", "Full Body", ["kb clean and press"]),
    e("Muscle-Up", "Full Body", ["muscle up", "bar muscle up"], "bodyweight"),
    e("Rope Climb", "Full Body", ["climbing rope"], "bodyweight"),
    e("Tire Flip", "Full Body", ["tyre flip"]),
    e("Sandbag Carry", "Full Body", ["sandbag walk"], "duration"),
    # Common Olympic / power basics
    e("Clean", "Full Body", ["squat clean", "full clean"]),
    e("Power Clean", "Full Body", ["powerclean"]),
    e("Hang Clean", "Full Body", ["hang power clean"]),
    e("Snatch", "Full Body", ["squat snatch", "full snatch"]),
    e("Power Snatch", "Full Body", ["powersnatch"]),
    e("Clean and Jerk", "Full Body", ["c&j", "clean & jerk"]),
    e("Push Jerk", "Full Body", ["barbell push jerk"]),
)

# ─── Mobility ────────────────────────────────────────────────────────────────
add(
    e("World's Greatest Stretch", "Mobility", ["worlds greatest stretch", "wgs"], "mobility"),
    e("Hip Flexor Stretch", "Mobility", ["hip flexor", "lunge stretch"], "mobility"),
    e("Couch Stretch", "Mobility", ["quad couch stretch"], "mobility"),
    e("Hamstring Stretch", "Mobility", ["hamstring", "standing hamstring stretch"], "mobility"),
    e("Calf Stretch", "Mobility", ["gastroc stretch"], "mobility"),
    e("Pigeon Stretch", "Mobility", ["pigeon pose", "figure four pigeon"], "mobility"),
    e("90-90 Hip Switch", "Mobility", ["90 90", "shin box"], "mobility"),
    e("Cat-Cow", "Mobility", ["cat cow", "cat camel"], "mobility"),
    e("Thoracic Rotation", "Mobility", ["t spine rotation", "open book"], "mobility"),
    e("Shoulder Pass-Through", "Mobility", ["pvc pass through", "shoulder dislocate"], "mobility"),
    e("Child's Pose", "Mobility", ["childs pose", "balasana"], "mobility"),
    e("Downward Dog", "Mobility", ["down dog"], "mobility"),
    e("Thread the Needle", "Mobility", ["thread needle"], "mobility"),
    e("Deep Squat Hold", "Mobility", ["asian squat", "pry squat"], "mobility"),
    e("Doorway Pec Stretch", "Mobility", ["chest doorway stretch", "pec stretch"], "mobility"),
    e("Cross-Body Shoulder Stretch", "Mobility", ["shoulder stretch"], "mobility"),
    e("Lat Stretch", "Mobility", ["lat doorway stretch"], "mobility"),
    e("Standing Quad Stretch", "Mobility", ["quad stretch"], "mobility"),
    e("Figure-Four Stretch", "Mobility", ["figure 4", "piriformis stretch"], "mobility"),
    e("Foam Roll Quadriceps", "Mobility", ["foam roll quads", "quad foam roll"], "mobility"),
    e("Foam Roll Hamstrings", "Mobility", ["hamstring foam roll"], "mobility"),
    e("Foam Roll IT Band", "Mobility", ["it band foam roll"], "mobility"),
    e("Foam Roll Calves", "Mobility", ["calf foam roll"], "mobility"),
    e("Foam Roll Lats", "Mobility", ["lat foam roll"], "mobility"),
    e("Wall Slide", "Mobility", ["wall angels"], "mobility"),
    e("Inchworm", "Mobility", ["inch worms"], "mobility"),
    e("Arm Circle", "Mobility", ["arm circles"], "mobility"),
    e("Hip Circles", "Mobility", ["hip circle warmup"], "mobility"),
    e("Ankle Circles", "Mobility", ["ankle mobility"], "mobility"),
    e("Neck Stretch", "Mobility", ["gentle neck stretch"], "mobility"),
)

# ─── Other ───────────────────────────────────────────────────────────────────
add(
    e("Neck Flexion", "Other", ["neck curl"]),
    e("Neck Extension", "Other", ["neck raise"]),
    e("Neck Lateral Flexion", "Other", ["neck side bend"]),
    e("Farmer Hold", "Other", ["farmers hold", "static farmer hold"], "duration"),
    e("Plate Pinch Hold", "Other", ["plate pinch", "pinch grip"], "duration"),
    e("Dead Hang", "Other", ["bar hang", "passive hang"], "duration"),
    e("Wrist Circles", "Other", ["wrist mobility"], "mobility"),
)


# Validate names before emitting generated Swift.
def norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", s.lower())


BLOCKED_NAMES = frozenset({
    "emom", "amrap", "tabata", "chipper",
    "barbellcomplex", "dumbbellcomplex", "kettlebellcomplex",
})

# Strip generic category/tag aliases that pollute search ranking.
GENERIC_ALIAS_BLOCKLIST = frozenset({
    "chest", "back", "shoulders", "arms", "legs", "glutes", "core", "cardio",
    "mobility", "full body", "other",
    "lats", "lat", "pecs", "pec", "triceps", "tricep", "tri", "biceps", "bicep",
    "machine", "cable", "barbell", "dumbbell", "bodyweight",
    "stretch", "warm up", "warmup",
})


def clean_aliases(aliases: list[str]) -> list[str]:
    cleaned: list[str] = []
    seen: set[str] = set()
    for alias in aliases:
        a = alias.strip()
        if not a:
            continue
        key = a.lower()
        if key in GENERIC_ALIAS_BLOCKLIST:
            continue
        if key in seen:
            continue
        seen.add(key)
        cleaned.append(a)
    return cleaned


seen_by_key: dict[str, Exercise] = {}
unique: list[Exercise] = []
dupes: list[tuple[str, Exercise, Exercise]] = []
for ex in EXERCISES:
    name, cat, aliases, lt = ex
    aliases = clean_aliases(aliases)
    ex = (name, cat, aliases, lt)
    key = norm(name)
    if key in BLOCKED_NAMES:
        print(f"WARNING: blocked non-exercise name skipped: {name}")
        continue
    if key in seen_by_key:
        dupes.append((key, seen_by_key[key], ex))
        continue
    seen_by_key[key] = ex
    unique.append(ex)

if dupes:
    print("ERROR: duplicate normalized exercise names found:")
    for key, first, duplicate in dupes:
        print(f"  {key}: {first[0]} ({first[1]}) conflicts with {duplicate[0]} ({duplicate[1]})")
    raise ValueError(f"Resolve {len(dupes)} duplicate exercise name(s) before generating the catalog.")

print(f"Total exercises: {len(unique)}")

SECTION_ORDER = [
    "Chest", "Back", "Shoulders", "Arms", "Legs", "Glutes",
    "Core", "Cardio", "Full Body", "Mobility", "Other",
]

by_cat: dict[str, list[Exercise]] = {c: [] for c in SECTION_ORDER}
for ex in unique:
    cat = ex[1]
    if cat not in by_cat:
        raise ValueError(f"Unknown category: {cat} for {ex[0]}")
    by_cat[cat].append(ex)

for cat in SECTION_ORDER:
    print(f"  {cat}: {len(by_cat[cat])}")

if not (280 <= len(unique) <= 350):
    print(f"WARNING: catalog size {len(unique)} is outside target 280-350")


def swift_aliases(aliases: list[str]) -> str:
    if not aliases:
        return "[]"
    parts = ", ".join(
        f'"{a.replace(chr(92), chr(92) + chr(92)).replace(chr(34), chr(92) + chr(34))}"'
        for a in aliases
    )
    return f"[{parts}]"


def swift_row(ex: Exercise) -> str:
    name, cat, aliases, lt = ex
    name_esc = name.replace("\\", "\\\\").replace('"', '\\"')
    if lt == "strength":
        return f'        row("{name_esc}", "{cat}", {swift_aliases(aliases)}),'
    return f'        row("{name_esc}", "{cat}", {swift_aliases(aliases)}, .{lt}),'


lines = [
    "import Foundation",
    "import SwiftData",
    "",
    "enum ExerciseCatalog {",
    "    /// Default logging type for catalog rows is ``ExerciseLoggingType/strength``.",
    "    private static func row(",
    "        _ name: String,",
    "        _ category: String,",
    "        _ aliases: [String],",
    "        _ loggingType: ExerciseLoggingType = .strength",
    "    ) -> (name: String, category: String, aliases: [String], loggingType: ExerciseLoggingType) {",
    "        (name, category, aliases, loggingType)",
    "    }",
    "",
    "    // Generated from scripts/generate_exercise_catalog.py — edit the generator, not this list.",
    "    // `category` is treated as muscle group.",
    "    static let items: [(name: String, category: String, aliases: [String], loggingType: ExerciseLoggingType)] = [",
]

for cat in SECTION_ORDER:
    lines.append(f"        // {cat}")
    for ex in by_cat[cat]:
        lines.append(swift_row(ex))
    lines.append("")

if lines[-1] == "":
    lines.pop()

lines.append("    ]")
lines.append("")
lines.append("""    static func seedIfNeeded(context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<Exercise>())
        var existingByNormalizedName: [String: Exercise] = [:]
        for exercise in existing {
            existingByNormalizedName[normalizedKey(exercise.name)] = exercise
        }

        for item in items {
            let metadata = encodeMetadata(item.aliases)
            let key = normalizedKey(item.name)
            if let stored = existingByNormalizedName[key] {
                // Keep user-facing name/category untouched; refresh metadata, source, and catalog logging type.
                stored.searchMetadata = metadata
                stored.source = .builtIn
                stored.loggingType = item.loggingType
            } else {
                context.insert(
                    Exercise(
                        name: item.name,
                        category: item.category,
                        searchMetadata: metadata,
                        source: .builtIn,
                        loggingType: item.loggingType
                    )
                )
            }
        }
        try context.save()
    }

    private static func encodeMetadata(_ aliases: [String]) -> String {
        aliases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\\n")
    }

    private static func normalizedKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
""")

out = Path(__file__).resolve().parents[1] / "JIMM" / "ExerciseCatalog.swift"
out.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"Wrote {out}")
