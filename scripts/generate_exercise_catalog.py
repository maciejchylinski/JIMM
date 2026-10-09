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
    e("Barbell Bench Press", "Chest", ["bench press", "flat bench", "bench", "chest press", "barbell", "chest"]),
    e("Dumbbell Bench Press", "Chest", ["db bench", "flat dumbbell press", "dumbbell press", "chest press", "pecs"]),
    e("Smith Machine Bench Press", "Chest", ["smith bench", "bench", "chest press"]),
    e("Machine Chest Press", "Chest", ["chest press machine", "machine press", "pecs", "chest"]),
    e("Hammer Strength Chest Press", "Chest", ["plate loaded chest press"]),
    e("Incline Barbell Bench Press", "Chest", ["incline bench"]),
    e("Incline Dumbbell Press", "Chest", ["incline db press"]),
    e("Incline Smith Machine Press", "Chest", ["incline smith bench"]),
    e("Incline Machine Press", "Chest", ["incline chest machine"]),
    e("Decline Barbell Bench Press", "Chest", ["decline bench"]),
    e("Decline Dumbbell Press", "Chest", ["decline db press"]),
    e("Decline Smith Machine Press", "Chest", ["decline smith bench"]),
    e("Machine Decline Press", "Chest", ["decline chest machine"]),
    e("Dumbbell Fly", "Chest", ["flat db fly"]),
    e("Incline Dumbbell Fly", "Chest", ["incline fly"]),
    e("Decline Dumbbell Fly", "Chest", ["decline fly"]),
    e("Cable Fly", "Chest", ["cable crossover"]),
    e("High-to-Low Cable Fly", "Chest", ["high low cable fly"]),
    e("Low-to-High Cable Fly", "Chest", ["low high cable fly"]),
    e("Incline Cable Fly", "Chest", ["incline cable crossover", "low cable fly", "upper chest cable fly"]),
    e("Single-Arm Cable Fly", "Chest", ["one arm cable fly"]),
    e("Pec Deck Fly", "Chest", ["machine fly", "pec deck"]),
    e("Cable Crossover", "Chest", ["standing crossover"]),
    e("Push-Up", "Chest", ["push up", "pushup", "push-up"], "bodyweight"),
    e("Wide Push-Up", "Chest", ["wide grip push up", "pushup"], "bodyweight"),
    e("Diamond Push-Up", "Chest", ["close grip push up", "pushup"], "bodyweight"),
    e("Decline Push-Up", "Chest", ["feet elevated push up", "pushup"], "bodyweight"),
    e("Incline Push-Up", "Chest", ["hands elevated push up", "pushup"], "bodyweight"),
    e("Weighted Push-Up", "Chest", ["loaded push up"]),
    e("Ring Push-Up", "Chest", ["gymnastic ring push up"], "bodyweight"),
    e("Archer Push-Up", "Chest", ["single arm assisted push up"], "bodyweight"),
    e("Chest Dip", "Chest", ["forward lean dip", "dip", "dips"], "bodyweight"),
    e("Weighted Dip", "Chest", ["weighted chest dip", "weighted triceps dip", "loaded dip", "dip", "dips", "triceps"]),
    e("Landmine Chest Press", "Chest", ["landmine press", "half kneeling landmine press"]),
    e("Single-Arm Landmine Chest Press", "Chest", ["one arm landmine press"]),
    e("Floor Press", "Chest", ["barbell floor press"]),
    e("Dumbbell Floor Press", "Chest", ["db floor press"]),
    e("Svend Press", "Chest", ["plate squeeze press"]),
    e("Guillotine Press", "Chest", ["neck bench press"]),
    e("Pin Press", "Chest", ["bench pin press"]),
    e("Spoto Press", "Chest", ["paused bench press"]),
    e("Board Press", "Chest", ["bench board press"]),
    e("Reverse-Grip Bench Press", "Chest", ["underhand bench press"]),
    e("Machine Fly", "Chest", ["seated fly machine"]),
    e("Standing Cable Press", "Chest", ["cable chest press"]),
    e("Resistance Band Chest Press", "Chest", ["band chest press"]),
    e("Kettlebell Floor Press", "Chest", ["kb floor press"]),
    e("Around the World", "Chest", ["dumbbell around the world"]),
    e("Pullover", "Chest", ["dumbbell pullover"]),
    e("Barbell Pullover", "Chest", ["straight arm pullover"]),
    e("Cable Pullover", "Chest", ["straight arm cable pullover"]),
    e("Squeeze Press", "Chest", ["dumbbell squeeze press"]),
    e("Iso-Lateral Chest Press", "Chest", ["hammer chest press"]),
    e("Plate-Loaded Chest Press", "Chest", ["converging chest press"]),
    e("Neutral-Grip Dumbbell Press", "Chest", ["hammer grip db press"]),
    e("Machine Incline Fly", "Chest", ["incline pec deck"]),
    e("Cross-Body Cable Press", "Chest", ["single arm cable press"]),
    e("Paused Dumbbell Bench Press", "Chest", ["paused db bench"]),
    e("Tempo Bench Press", "Chest", ["slow bench press"]),
    e("Feet-Up Bench Press", "Chest", ["feet on bench bench press"]),
    e("Larsen Press", "Chest", ["legs up bench press"]),
)

# ─── Back ────────────────────────────────────────────────────────────────────
add(
    e("Pull-Up", "Back", ["pull up", "pullup", "pull-up", "bodyweight", "lats"], "bodyweight"),
    e("Chin-Up", "Back", ["chin up", "chinup", "chin-up", "bodyweight", "lats"], "bodyweight"),
    e("Neutral-Grip Pull-Up", "Back", ["parallel pull up"], "bodyweight"),
    e("Wide-Grip Pull-Up", "Back", ["wide pull up"], "bodyweight"),
    e("Weighted Pull-Up", "Back", ["loaded pull up"]),
    e("Assisted Pull-Up", "Back", ["band assisted pull up"], "bodyweight"),
    e("Lat Pulldown", "Back", ["lat pull down", "pulldown", "pull-down", "pull down", "lats", "cable", "back"]),
    e("Wide-Grip Lat Pulldown", "Back", ["wide pulldown", "wide grip pull-down", "pull-down", "pull down", "pulldown", "lats", "back"]),
    e("Close-Grip Lat Pulldown", "Back", ["close pulldown", "close grip pull-down", "pull-down", "pull down", "pulldown", "lats", "back"]),
    e("Neutral-Grip Lat Pulldown", "Back", ["v-bar pulldown", "neutral pull-down", "pull-down", "pull down", "pulldown", "lats", "back"]),
    e("Reverse-Grip Lat Pulldown", "Back", ["underhand lat pulldown", "reverse pull-down", "pull-down", "pull down", "pulldown", "lats", "back"]),
    e("Single-Arm Lat Pulldown", "Back", ["one arm pulldown", "single arm pull-down", "pull-down", "pull down", "pulldown", "lats", "back"]),
    e("Straight-Arm Pulldown", "Back", ["lat prayer", "cable lat prayer", "straight arm pull-down", "pulldown", "pull-down", "lats", "back"]),
    e("Behind-the-Neck Lat Pulldown", "Back", ["behind neck pulldown"]),
    e("Seated Cable Row", "Back", ["cable row", "seated row", "row", "back", "lats"]),
    e("Wide-Grip Seated Row", "Back", ["wide cable row", "cable row", "row"]),
    e("Close-Grip Seated Row", "Back", ["close cable row", "cable row", "row"]),
    e("Single-Arm Cable Row", "Back", ["one arm cable row"]),
    e("Chest-Supported Row", "Back", ["incline bench row"]),
    e("Barbell Row", "Back", ["bent over row", "bb row", "row", "back", "lats"]),
    e("Underhand Barbell Row", "Back", ["reverse grip row"]),
    e("Pendlay Row", "Back", ["dead stop row"]),
    e("Yates Row", "Back", ["semi upright row"]),
    e("T-Bar Row", "Back", ["landmine row"]),
    e("Machine Row", "Back", ["plate loaded row", "machine row", "row", "back"]),
    e("Single-Arm Dumbbell Row", "Back", ["one arm row", "db row", "dumbbell row", "row", "back", "lats"]),
    e("Kroc Row", "Back", ["heavy db row"]),
    e("Meadows Row", "Back", ["landmine single arm row"]),
    e("Chest-Supported Dumbbell Row", "Back", ["incline db row"]),
    e("Chest-Supported Machine Row", "Back", ["machine supported row"]),
    e("Inverted Row", "Back", ["bodyweight row"], "bodyweight"),
    e("Ring Row", "Back", ["suspension row"], "bodyweight"),
    e("Deadlift", "Back", ["conventional deadlift", "dead lift"]),
    e("Sumo Deadlift", "Back", ["wide stance deadlift"]),
    e("Trap Bar Deadlift", "Back", ["hex bar deadlift"]),
    e("Deficit Deadlift", "Back", ["elevated pull deadlift"]),
    e("Block Pull", "Back", ["rack pull from blocks"]),
    e("Rack Pull", "Back", ["partial deadlift"]),
    e("Snatch-Grip Deadlift", "Back", ["snatch grip deadlift", "wide grip deadlift"]),
    e("Stiff-Leg Deadlift", "Back", ["straight leg deadlift"]),
    e("Good Morning", "Back", ["barbell good morning"]),
    e("Back Extension", "Back", ["hyperextension", "roman chair back extension"]),
    e("45-Degree Back Extension", "Back", ["glute ham raise setup extension"]),
    e("Reverse Hyperextension", "Back", ["reverse hyper", "reverse hyper machine"]),
    e("Shrug", "Back", ["barbell shrug"]),
    e("Dumbbell Shrug", "Back", ["db shrug"]),
    e("Trap Bar Shrug", "Back", ["hex bar shrug"]),
    e("Machine Shrug", "Back", ["shrug machine"]),
    e("Farmer Shrug", "Back", ["farmer hold shrug"]),
    e("Seal Row", "Back", ["chest supported barbell row"]),
    e("Helms Row", "Back", ["chest supported landmine row"]),
    e("Renegade Row", "Back", ["plank db row"]),
    e("Cable High Row", "Back", ["high cable row"]),
    e("Machine High Row", "Back", ["hammer high row"]),
    e("Iso-Lateral Row", "Back", ["hammer row"]),
    e("Landmine Row", "Back", ["two hand landmine row"]),
    e("Kettlebell Row", "Back", ["kb bent over row"]),
    e("Resistance Band Row", "Back", ["band row"]),
    e("Jefferson Deadlift", "Back", ["jefferson lift"]),
    e("Deficit Barbell Row", "Back", ["elevated row"]),
    e("Paused Barbell Row", "Back", ["paused bent over row"]),
    e("Gorilla Row", "Back", ["kettlebell gorilla row"]),
    e("Machine Pullover", "Back", ["nautilus pullover", "lat pullover machine", "pullover machine"]),
    e("Rope Climb", "Back", ["climbing rope"], "bodyweight"),
    e("Muscle-Up", "Back", ["bar muscle up"], "bodyweight"),
    e("Scapular Pull-Up", "Back", ["scap pull up"], "bodyweight"),
    e("Scapular Push-Up", "Back", ["scap push up"], "bodyweight"),
    e("Hammer Strength Pulldown", "Back", ["plate pulldown"]),
    e("Hammer Strength Row", "Back", ["plate row"]),
    e("Smith Machine Row", "Back", ["smith bent over row"]),
    e("Smith Machine Shrug", "Back", ["smith shrug"]),
    e("Cable Shrug", "Back", ["low cable shrug"]),
    e("Power Shrug", "Back", ["explosive shrug"]),
)

# ─── Shoulders ─────────────────────────────────────────────────────────────────
add(
    e("Barbell Overhead Press", "Shoulders", ["ohp", "military press", "overhead press", "shoulder press", "press", "barbell", "shoulders"]),
    e("Seated Barbell Overhead Press", "Shoulders", ["seated ohp", "seated overhead press", "barbell shoulder press"]),
    e("Push Press", "Shoulders", ["barbell push press"]),
    e("Behind-the-Neck Press", "Shoulders", ["btnp"]),
    e("Dumbbell Shoulder Press", "Shoulders", ["db ohp", "dumbbell overhead press", "shoulder press", "dumbbell press", "shoulders"]),
    e("Seated Dumbbell Shoulder Press", "Shoulders", ["seated db press", "seated dumbbell press", "dumbbell overhead press", "shoulder press"]),
    e("Standing Dumbbell Shoulder Press", "Shoulders", ["standing db press", "standing dumbbell press", "dumbbell overhead press", "shoulder press"]),
    e("Arnold Press", "Shoulders", ["arnold dumbbell press"]),
    e("Machine Shoulder Press", "Shoulders", ["shoulder press machine", "machine overhead press", "machine press", "shoulders"]),
    e("Plate-Loaded Shoulder Press", "Shoulders", ["hammer strength shoulder press", "iso-lateral shoulder press", "machine shoulder press", "plate loaded press"]),
    e("Smith Machine Overhead Press", "Shoulders", ["smith ohp", "smith machine shoulder press", "smith shoulder press", "overhead press"]),
    e("Landmine Shoulder Press", "Shoulders", ["standing landmine press"]),
    e("Single-Arm Landmine Shoulder Press", "Shoulders", ["one arm landmine shoulder press"]),
    e("Kettlebell Press", "Shoulders", ["kb overhead press"]),
    e("Bottoms-Up Kettlebell Press", "Shoulders", ["kb bottoms up press"]),
    e("Z Press", "Shoulders", ["seated floor press shoulders"]),
    e("Viking Press", "Shoulders", ["landmine viking press"]),
    e("Bradford Press", "Shoulders", ["front to back press"]),
    e("Cuban Press", "Shoulders", ["external rotation press"]),
    e("Dumbbell Lateral Raise", "Shoulders", ["side raise", "lateral raise", "delt", "delts", "shoulders"]),
    e("Cable Lateral Raise", "Shoulders", ["cable side raise", "side delt cable raise"]),
    e("Machine Lateral Raise", "Shoulders", ["lateral raise machine", "side delt machine", "machine side raise"]),
    e("Single-Arm Cable Lateral Raise", "Shoulders", ["one arm cable lateral raise", "single arm cable side raise", "side delt cable raise"]),
    e("Lean-Away Cable Lateral Raise", "Shoulders", ["leaning lateral raise"]),
    e("Seated Lateral Raise", "Shoulders", ["seated side raise"]),
    e("Partial Lateral Raise", "Shoulders", ["heavy partial lateral"]),
    e("Dumbbell Front Raise", "Shoulders", ["front raise"]),
    e("Cable Front Raise", "Shoulders", ["cable front raise"]),
    e("Plate Front Raise", "Shoulders", ["plate raise"]),
    e("Barbell Front Raise", "Shoulders", ["bb front raise"]),
    e("Rear Delt Fly", "Shoulders", ["reverse fly"]),
    e("Reverse Pec Deck", "Shoulders", ["rear delt machine"]),
    e("Bent-Over Rear Delt Raise", "Shoulders", ["bent over rear raise"]),
    e("Cable Rear Delt Fly", "Shoulders", ["cable reverse fly"]),
    e("Face Pull", "Shoulders", ["rope face pull", "rear delt", "rear delts", "rope", "cable", "shoulders"]),
    e("Upright Row", "Shoulders", ["barbell upright row"]),
    e("Dumbbell Upright Row", "Shoulders", ["db upright row"]),
    e("Cable Upright Row", "Shoulders", ["cable upright row"]),
    e("Smith Machine Upright Row", "Shoulders", ["smith upright row"]),
    e("Lu Raise", "Shoulders", ["lu lateral raise complex"]),
    e("Y Raise", "Shoulders", ["prone y raise"]),
    e("T Raise", "Shoulders", ["prone t raise"]),
    e("W Raise", "Shoulders", ["prone w raise"]),
    e("Bus Driver", "Shoulders", ["plate rotation press"]),
    e("Landmine Lateral Raise", "Shoulders", ["landmine side raise"]),
    e("Kettlebell Halo", "Shoulders", ["kb halo"]),
    e("Band Pull-Apart", "Shoulders", ["band pull apart"]),
    e("Scaption Raise", "Shoulders", ["scapular plane raise"]),
    e("Cable Y-Raise", "Shoulders", ["cable y raise"]),
    e("Handstand Push-Up", "Shoulders", ["wall handstand press"], "bodyweight"),
    e("Pike Push-Up", "Shoulders", ["pike press"], "bodyweight"),
    e("Wall Walk", "Shoulders", ["handstand walk prep"], "bodyweight"),
    e("Neck Flexion", "Shoulders", ["neck curl"]),
    e("Neck Extension", "Shoulders", ["neck extension"]),
    e("Neck Lateral Flexion", "Shoulders", ["side neck bend"]),
    e("Plate Neck Harness Extension", "Shoulders", ["neck harness"]),
    e("Cross-Body Cable Lateral Raise", "Shoulders", ["cross cable lateral"]),
    e("Single-Arm Cable Front Raise", "Shoulders", ["one arm front raise"]),
    e("Resistance Band Lateral Raise", "Shoulders", ["band lateral raise"]),
    e("Resistance Band Overhead Press", "Shoulders", ["band ohp"]),
    e("Pin Press Overhead", "Shoulders", ["overhead pin press"]),
)

# ─── Biceps ────────────────────────────────────────────────────────────────────
add(
    e("Barbell Curl", "Biceps", ["bb curl", "curl", "barbell", "biceps"]),
    e("EZ-Bar Curl", "Biceps", ["ez curl", "ez bar", "curl", "biceps"]),
    e("Dumbbell Curl", "Biceps", ["db curl", "dumbbell", "curl", "biceps"]),
    e("Alternating Dumbbell Curl", "Biceps", ["alt db curl"]),
    e("Incline Dumbbell Curl", "Biceps", ["incline curl"]),
    e("Seated Dumbbell Curl", "Biceps", ["seated curl"]),
    e("Concentration Curl", "Biceps", ["concentration db curl"]),
    e("Preacher Curl", "Biceps", ["preacher bench curl"]),
    e("Machine Preacher Curl", "Biceps", ["preacher machine"]),
    e("Spider Curl", "Biceps", ["prone incline curl"]),
    e("Cable Curl", "Biceps", ["standing cable curl"]),
    e("High Cable Curl", "Biceps", ["overhead cable curl"]),
    e("Bayesian Cable Curl", "Biceps", ["behind body cable curl"]),
    e("Hammer Curl", "Biceps", ["neutral grip curl", "hammer", "biceps"]),
    e("Cross-Body Hammer Curl", "Biceps", ["cross body curl"]),
    e("Rope Hammer Curl", "Biceps", ["cable hammer curl"]),
    e("Reverse Curl", "Biceps", ["pronated curl"]),
    e("Drag Curl", "Biceps", ["barbell drag curl"]),
    e("Cheat Curl", "Biceps", ["heavy cheat curl"]),
    e("21s Curl", "Biceps", ["barbell 21s"]),
    e("Zottman Curl", "Biceps", ["zottman db curl"]),
    e("Pinwheel Curl", "Biceps", ["offset hammer curl"]),
    e("Machine Curl", "Biceps", ["biceps curl machine"]),
    e("Cable Preacher Curl", "Biceps", ["cable preacher curl"]),
    e("Single-Arm Cable Curl", "Biceps", ["one arm cable curl"]),
    e("Resistance Band Curl", "Biceps", ["band curl"]),
    e("Kettlebell Curl", "Biceps", ["kb curl"]),
    e("Fat-Grip Curl", "Biceps", ["thick bar curl"]),
    e("Wrist Curl", "Biceps", ["barbell wrist curl"]),
    e("Reverse Wrist Curl", "Biceps", ["extension wrist curl"]),
    e("Behind-the-Back Wrist Curl", "Biceps", ["behind back wrist curl"]),
    e("Dumbbell Wrist Curl", "Biceps", ["db wrist curl"]),
    e("Farmer Hold", "Biceps", ["static farmer hold"], "duration"),
    e("Plate Pinch Hold", "Biceps", ["pinch grip hold"], "duration"),
    e("Towel Pull-Up", "Biceps", ["towel grip pull up"], "bodyweight"),
    e("Ring Curl", "Biceps", ["suspension curl"], "bodyweight"),
    e("Cable Drag Curl", "Biceps", ["cable drag curl"]),
    e("Lying Cable Curl", "Biceps", ["floor cable curl"]),
    e("Incline Cable Curl", "Biceps", ["incline bench cable curl"]),
    e("Machine Hammer Curl", "Biceps", ["neutral curl machine"]),
    e("Iso-Lateral Curl", "Biceps", ["hammer curl machine"]),
    e("Tempo Barbell Curl", "Biceps", ["slow curl"]),
    e("Paused Barbell Curl", "Biceps", ["paused curl"]),
    e("Cable Rope Curl", "Biceps", ["rope biceps curl"]),
    e("Landmine Curl", "Biceps", ["landmine biceps curl"]),
)

# ─── Triceps ───────────────────────────────────────────────────────────────────
add(
    e("Close-Grip Bench Press", "Triceps", ["cg bench", "close grip bench", "tricep bench", "triceps bench"]),
    e("Skull Crusher", "Triceps", ["lying triceps extension", "lying tricep extension", "ez bar", "triceps", "tricep"]),
    e("EZ-Bar Skull Crusher", "Triceps", ["ez skull crusher", "ez bar skullcrusher", "lying triceps extension", "triceps", "tricep"]),
    e("Barbell Overhead Triceps Extension", "Triceps", ["standing bar extension", "overhead tricep extension"]),
    e("Seated Dumbbell Overhead Triceps Extension", "Triceps", ["seated db extension", "dumbbell overhead extension", "overhead tricep extension"]),
    e("Single-Arm Dumbbell Overhead Triceps Extension", "Triceps", ["one arm db extension", "single arm dumbbell tricep extension"]),
    e("Cable Triceps Pushdown", "Triceps", ["cable pushdown", "tricep pushdown", "triceps pressdown", "pushdown", "pressdown", "cable", "triceps", "tricep", "tri"]),
    e("Rope Triceps Pushdown", "Triceps", ["rope pushdown", "rope pressdown", "cable rope pushdown", "pushdown", "pressdown", "rope", "cable", "triceps", "tricep", "tri"]),
    e("Straight Bar Triceps Pushdown", "Triceps", ["straight-bar pushdown", "straight bar pushdown", "bar pushdown", "straight bar pressdown", "pushdown", "pressdown", "cable", "triceps", "tricep", "tri"]),
    e("V-Bar Triceps Pushdown", "Triceps", ["v-bar pushdown", "v bar pushdown", "v bar triceps pushdown", "v-bar pressdown", "pushdown", "pressdown", "cable", "triceps", "tricep", "tri"]),
    e("Reverse Grip Triceps Pushdown", "Triceps", ["reverse-grip pushdown", "underhand pushdown", "reverse grip pressdown", "pushdown", "pressdown", "cable", "triceps", "tricep", "tri"]),
    e("Single-Arm Cable Triceps Pushdown", "Triceps", ["single arm cable pushdown", "one arm pushdown", "one arm cable pushdown", "pushdown", "pressdown", "cable", "triceps", "tricep", "tri"]),
    e("Single-Arm Rope Triceps Pushdown", "Triceps", ["single arm rope pushdown", "one arm rope pushdown", "rope pressdown", "pushdown", "pressdown", "rope", "cable", "triceps", "tricep", "tri"]),
    e("Cable Overhead Triceps Extension", "Triceps", ["overhead cable triceps extension", "cable overhead extension", "cable tricep extension", "triceps extension", "tricep extension"]),
    e("Rope Overhead Triceps Extension", "Triceps", ["rope overhead extension", "overhead rope extension", "rope cable extension", "triceps extension", "tricep extension", "rope", "cable"]),
    e("Dumbbell Skull Crusher", "Triceps", ["db skull crusher", "lying dumbbell triceps extension", "lying db triceps extension", "dumbbell tricep extension"]),
    e("JM Press", "Triceps", ["jm bench press"]),
    e("Bench Dip", "Triceps", ["triceps bench dip", "tricep bench dip", "dip", "dips"], "bodyweight"),
    e("Parallel Bar Dip", "Triceps", ["triceps dip", "tricep dip", "bodyweight dip", "dip", "dips"], "bodyweight"),
    e("Ring Dip", "Triceps", ["gymnastic dip"], "bodyweight"),
    e("Assisted Triceps Dip", "Triceps", ["assisted dip", "assisted dip machine", "machine triceps dip", "dip machine", "tricep dip", "dip", "dips"], "bodyweight"),
    e("Kickback", "Triceps", ["dumbbell kickback"]),
    e("Cable Triceps Kickback", "Triceps", ["cable kickback", "tricep kickback", "triceps kickback"]),
    e("Tate Press", "Triceps", ["lying db tate press"]),
    e("California Press", "Triceps", ["hybrid press extension"]),
    e("Floor Press Close-Grip", "Triceps", ["close grip floor press"]),
    e("Board Press Close-Grip", "Triceps", ["close grip board press"]),
    e("Pin Press Close-Grip", "Triceps", ["close grip pin press"]),
    e("Machine Triceps Extension", "Triceps", ["triceps machine", "tricep extension machine", "machine tricep extension"]),
    e("Resistance Band Pushdown", "Triceps", ["band pushdown"]),
    e("Resistance Band Overhead Extension", "Triceps", ["band overhead extension"]),
    e("Bodyweight Triceps Extension", "Triceps", ["bodyweight skull crusher"], "bodyweight"),
    e("Suspension Triceps Press", "Triceps", ["trx triceps press"], "bodyweight"),
    e("Cross-Body Cable Extension", "Triceps", ["single arm cross extension"]),
    e("Tempo Skull Crusher", "Triceps", ["slow skull crusher"]),
    e("Paused Close-Grip Bench Press", "Triceps", ["paused cg bench"]),
    e("Rolling Dumbbell Extension", "Triceps", ["rolling db extension"]),
    e("Cable Concentration Extension", "Triceps", ["kneeling cable extension"]),
    e("Kettlebell Overhead Extension", "Triceps", ["kb triceps extension"]),
    e("Landmine Triceps Extension", "Triceps", ["landmine extension"]),
)

# ─── Legs ──────────────────────────────────────────────────────────────────────
add(
    e("Back Squat", "Legs", ["barbell squat", "squat", "back squat", "legs", "quads"]),
    e("Low-Bar Back Squat", "Legs", ["low bar squat", "squat", "back squat"]),
    e("High-Bar Back Squat", "Legs", ["high bar squat", "squat", "back squat"]),
    e("Front Squat", "Legs", ["front rack squat", "front squat", "squat", "legs"]),
    e("Safety Bar Squat", "Legs", ["ssb squat"]),
    e("Zercher Squat", "Legs", ["zercher squat"]),
    e("Box Squat", "Legs", ["box back squat"]),
    e("Pause Squat", "Legs", ["paused squat"]),
    e("Tempo Squat", "Legs", ["slow squat"]),
    e("Anderson Squat", "Legs", ["pin squat from bottom"]),
    e("Overhead Squat", "Legs", ["oh squat"]),
    e("Goblet Squat", "Legs", ["dumbbell goblet squat"]),
    e("Kettlebell Goblet Squat", "Legs", ["kb goblet squat"]),
    e("Hack Squat", "Legs", ["machine hack squat"]),
    e("Pendulum Squat", "Legs", ["pendulum squat machine"]),
    e("V-Squat", "Legs", ["v squat machine"]),
    e("Belt Squat", "Legs", ["belt squat machine"]),
    e("Leg Press", "Legs", ["sled leg press", "leg press", "machine", "quads"]),
    e("Single-Leg Press", "Legs", ["one leg press"]),
    e("Horizontal Leg Press", "Legs", ["seated leg press"]),
    e("Sissy Squat", "Legs", ["sissy squat machine"], "bodyweight"),
    e("Spanish Squat", "Legs", ["band spanish squat"]),
    e("Split Squat", "Legs", ["static lunge"]),
    e("Bulgarian Split Squat", "Legs", ["bss", "rear foot elevated split squat", "bulgarian", "split squat", "lunge", "legs"]),
    e("Walking Lunge", "Legs", ["walking lunges"]),
    e("Reverse Lunge", "Legs", ["backward lunge"]),
    e("Forward Lunge", "Legs", ["step forward lunge"]),
    e("Lateral Lunge", "Legs", ["side lunge"]),
    e("Curtsy Lunge", "Legs", ["curtsy squat"]),
    e("Deficit Reverse Lunge", "Legs", ["elevated reverse lunge"]),
    e("Step-Up", "Legs", ["box step up"]),
    e("Deficit Step-Up", "Legs", ["high step up"]),
    e("Romanian Deadlift", "Legs", ["rdl", "romanian", "hinge", "hamstrings", "glutes", "dead lift"]),
    e("Single-Leg Romanian Deadlift", "Legs", ["single leg rdl"]),
    e("Leg Extension", "Legs", ["quad extension", "quads", "machine", "leg extension"]),
    e("Single-Leg Extension", "Legs", ["unilateral leg extension"]),
    e("Lying Leg Curl", "Legs", ["prone leg curl", "hamstring curl", "hamstrings", "machine", "leg curl"]),
    e("Seated Leg Curl", "Legs", ["hamstring curl machine", "leg curl", "hamstrings", "machine"]),
    e("Standing Leg Curl", "Legs", ["standing ham curl"]),
    e("Nordic Curl", "Legs", ["nordic hamstring curl"], "bodyweight"),
    e("Glute-Ham Raise", "Legs", ["ghr"]),
    e("Reverse Nordic", "Legs", ["reverse nordic curl"], "bodyweight"),
    e("Copenhagen Plank", "Legs", ["adductor plank"], "duration"),
    e("Standing Calf Raise", "Legs", ["calf raise", "calves", "calf", "standing", "machine"]),
    e("Seated Calf Raise", "Legs", ["seated calf", "calves", "calf", "seated", "machine"]),
    e("Leg Press Calf Raise", "Legs", ["sled calf raise"]),
    e("Donkey Calf Raise", "Legs", ["donkey calf"]),
    e("Smith Machine Calf Raise", "Legs", ["smith calf raise"]),
    e("Tibialis Raise", "Legs", ["tib bar raise"]),
    e("Seated Tibialis Raise", "Legs", ["tibialis anterior machine"]),
    e("Hip Adduction Machine", "Legs", ["adductor machine"]),
    e("Hip Abduction Machine", "Legs", ["abductor machine"]),
    e("Smith Machine Squat", "Legs", ["smith squat"]),
    e("Smith Machine Lunge", "Legs", ["smith lunge"]),
    e("Landmine Squat", "Legs", ["landmine squat"]),
    e("Landmine Lunge", "Legs", ["landmine lunge"]),
    e("Jefferson Squat", "Legs", ["jefferson squat"]),
    e("Pistol Squat", "Legs", ["single leg squat"], "bodyweight"),
    e("Shrimp Squat", "Legs", ["quad dominant pistol"], "bodyweight"),
    e("Cossack Squat", "Legs", ["side squat"], "bodyweight"),
    e("Wall Sit", "Legs", ["isometric squat hold"], "duration"),
    e("Jump Squat", "Legs", ["barbell jump squat"]),
    e("Vertical Jump", "Legs", ["standing vertical jump"], "bodyweight"),
    e("Hatfield Squat", "Legs", ["ssb hatfield squat"]),
    e("Kang Squat", "Legs", ["hybrid squat good morning"]),
    e("Trap Bar Carry", "Legs", ["hex bar carry"]),
    e("Banded Squat", "Legs", ["resistance band squat"]),
    e("Banded Leg Curl", "Legs", ["band hamstring curl"]),
    e("Terminal Knee Extension", "Legs", ["tke band"]),
    e("Peterson Step-Up", "Legs", ["knee over toe step up"]),
    e("Poliquin Step-Up", "Legs", ["elevated step up"]),
    e("Heels-Elevated Squat", "Legs", ["quad bias squat"]),
    e("Toes-Elevated Squat", "Legs", ["glute bias squat"]),
)

# ─── Glutes ────────────────────────────────────────────────────────────────────
add(
    e("Barbell Hip Thrust", "Glutes", ["hip thrust", "hipthrust", "glutes", "bridge"]),
    e("Dumbbell Hip Thrust", "Glutes", ["db hip thrust", "hip thrust", "glutes"]),
    e("Machine Hip Thrust", "Glutes", ["hip thrust machine"]),
    e("Glute Drive Machine", "Glutes", ["glute drive", "hip thrust machine", "machine hip thrust", "glutes"]),
    e("Banded Hip Thrust", "Glutes", ["resistance band hip thrust"]),
    e("Single-Leg Hip Thrust", "Glutes", ["one leg hip thrust"]),
    e("Glute Bridge", "Glutes", ["barbell glute bridge", "glute bridge", "bridge", "glutes"]),
    e("Single-Leg Glute Bridge", "Glutes", ["one leg bridge"]),
    e("Frog Pump", "Glutes", ["frog bridge"]),
    e("Kas Glute Bridge", "Glutes", ["short range hip thrust"]),
    e("Cable Glute Kickback", "Glutes", ["glute kickback", "cable kickback", "cable glute extension"]),
    e("Machine Glute Kickback", "Glutes", ["kickback machine"]),
    e("Donkey Kick", "Glutes", ["quadruped kickback"], "bodyweight"),
    e("Fire Hydrant", "Glutes", ["quadruped hip abduction"], "bodyweight"),
    e("Clamshell", "Glutes", ["band clamshell"]),
    e("Seated Hip Abduction Machine", "Glutes", ["hip abduction machine", "abductor machine", "seated abductor machine", "glute abduction", "glutes"]),
    e("Cable Hip Abduction", "Glutes", ["standing cable abduction"]),
    e("Banded Lateral Walk", "Glutes", ["monster walk", "lateral band walk", "side step band", "band side walk"]),
    e("Cable Pull-Through", "Glutes", ["rope pull through"]),
    e("Step-Down", "Glutes", ["eccentric step down"]),
    e("Frog Hip Thrust", "Glutes", ["frog stance thrust"]),
    e("Smith Machine Hip Thrust", "Glutes", ["smith hip thrust"]),
    e("Landmine RDL", "Glutes", ["landmine rdl"]),
    e("Paused Hip Thrust", "Glutes", ["isometric hip thrust"]),
    e("B-stance Hip Thrust", "Glutes", ["staggered hip thrust"]),
    e("Hip Extension Machine", "Glutes", ["glute extension machine"]),
    e("Standing Glute Pushdown", "Glutes", ["cable glute press"]),
    e("Reverse Lunge to Knee Drive", "Glutes", ["lunge knee drive"]),
    e("Cable Step-Up", "Glutes", ["cable resisted step up"]),
    e("Sandbag Bear Hug Squat", "Glutes", ["bear hug squat"]),
)

# ─── Core ──────────────────────────────────────────────────────────────────────
add(
    e("Plank", "Core", ["front plank", "plank", "hold", "core"], "duration"),
    e("Side Plank", "Core", ["lateral plank", "side plank", "plank", "hold", "core"], "duration"),
    e("RKC Plank", "Core", ["hardstyle plank"], "duration"),
    e("Weighted Plank", "Core", ["loaded plank"], "duration"),
    e("Plank Shoulder Tap", "Core", ["shoulder tap plank"], "bodyweight"),
    e("Dead Bug", "Core", ["deadbug"], "bodyweight"),
    e("Bird Dog", "Core", ["quadruped bird dog"], "bodyweight"),
    e("Hollow Body Hold", "Core", ["hollow hold"], "duration"),
    e("Arch Hold", "Core", ["superman hold"], "duration"),
    e("Crunch", "Core", ["ab crunch", "crunch", "abs", "core", "abdominal"], "bodyweight"),
    e("Bicycle Crunch", "Core", ["cross body crunch"], "bodyweight"),
    e("Reverse Crunch", "Core", ["hip lift crunch"], "bodyweight"),
    e("Sit-Up", "Core", ["ab sit up", "sit up", "situp", "sit-up", "abs", "core"], "bodyweight"),
    e("Weighted Sit-Up", "Core", ["loaded sit up"]),
    e("V-Up", "Core", ["jackknife"], "bodyweight"),
    e("Toes to Bar", "Core", ["ttb"], "bodyweight"),
    e("Hanging Leg Raise", "Core", ["hanging knee raise"], "bodyweight"),
    e("Hanging Knee Raise", "Core", ["captain knee raise"], "bodyweight"),
    e("Captain Chair Leg Raise", "Core", ["vertical leg raise"], "bodyweight"),
    e("Captain Chair Knee Raise", "Core", ["roman chair knee raise"], "bodyweight"),
    e("Cable Crunch", "Core", ["kneeling cable crunch"]),
    e("Machine Crunch", "Core", ["ab machine"]),
    e("Decline Sit-Up", "Core", ["decline ab sit up"], "bodyweight"),
    e("GHD Sit-Up", "Core", ["glute ham sit up"], "bodyweight"),
    e("Pallof Press", "Core", ["anti rotation press"]),
    e("Pallof Hold", "Core", ["anti rotation hold"], "duration"),
    e("Landmine Rotation", "Core", ["landmine twist"]),
    e("Russian Twist", "Core", ["weighted russian twist"]),
    e("Medicine Ball Slam", "Core", ["ball slam"]),
    e("Wood Chop", "Core", ["cable woodchop"]),
    e("High-to-Low Wood Chop", "Core", ["diagonal chop down"]),
    e("Low-to-High Wood Chop", "Core", ["diagonal chop up"]),
    e("Ab Wheel Rollout", "Core", ["ab rollout"], "bodyweight"),
    e("Barbell Rollout", "Core", ["barbell ab rollout"]),
    e("Stability Ball Rollout", "Core", ["swiss ball rollout"], "bodyweight"),
    e("Dragon Flag", "Core", ["dragonflag"], "bodyweight"),
    e("L-Sit", "Core", ["l sit hold"], "duration"),
    e("Hanging L-Sit", "Core", ["bar l sit"], "duration"),
    e("Windmill", "Core", ["kb windmill"]),
    e("Stir the Pot", "Core", ["stability ball plank"], "bodyweight"),
    e("Mountain Climber", "Core", ["running plank"], "bodyweight"),
    e("Dead Bug with Band", "Core", ["band resisted dead bug"]),
    e("Cable Pallof Press", "Core", ["standing pallof"]),
    e("Side Bend", "Core", ["dumbbell side bend"]),
    e("Saxon Side Bend", "Core", ["plate side bend"]),
    e("Hip Dip Side Plank", "Core", ["side plank dip"], "bodyweight"),
    e("Copenhagen Side Plank", "Core", ["copenhagen side"], "duration"),
    e("Hollow Rock", "Core", ["hollow body rock"], "bodyweight"),
    e("V-Sit", "Core", ["v sit"], "duration"),
    e("Jackknife", "Core", ["bench jackknife"], "bodyweight"),
    e("Flutter Kick", "Core", ["scissor kick"], "bodyweight"),
    e("Leg Raise", "Core", ["lying leg raise", "leg raise", "abs", "core"], "bodyweight"),
    e("McGill Curl-Up", "Core", ["curl up"]),
    e("Side Crunch", "Core", ["oblique crunch"], "bodyweight"),
    e("Oblique Cable Crunch", "Core", ["kneeling oblique crunch"]),
    e("Landmine Anti-Rotation", "Core", ["landmine pallof"]),
    e("Plank Up-Down", "Core", ["plank to push up"], "bodyweight"),
    e("Body Saw", "Core", ["slider plank"], "bodyweight"),
    e("TRX Fallout", "Core", ["suspension fallout"], "bodyweight"),
    e("Resistance Band Pallof", "Core", ["band pallof"]),
)

# ─── Cardio ────────────────────────────────────────────────────────────────────
add(
    e("Treadmill Walk", "Cardio", ["incline walk", "walk", "walking", "treadmill", "cardio"], "cardio"),
    e("Treadmill Run", "Cardio", ["indoor run", "run", "running", "treadmill", "cardio"], "cardio"),
    e("Treadmill Incline Walk", "Cardio", ["12-3-30 walk", "treadmill walk", "walking"], "cardio"),
    e("Outdoor Walk", "Cardio", ["walking", "walk"], "cardio"),
    e("Outdoor Run", "Cardio", ["jog", "running", "run"], "cardio"),
    e("Outdoor Sprint", "Cardio", ["sprints"], "cardio"),
    e("Trail Run", "Cardio", ["trail running"], "cardio"),
    e("Stationary Bike", "Cardio", ["exercise bike", "bike", "cycling", "stationary bike", "cardio"], "cardio"),
    e("Upright Bike", "Cardio", ["upright cycle", "bike", "cycling"], "cardio"),
    e("Recumbent Bike", "Cardio", ["recumbent cycle", "bike", "cycling"], "cardio"),
    e("Spin Bike", "Cardio", ["indoor cycling", "bike", "cycling"], "cardio"),
    e("Air Bike", "Cardio", ["assault bike", "fan bike"], "cardio"),
    e("Elliptical", "Cardio", ["cross trainer", "elliptical trainer", "cardio"], "cardio"),
    e("Rowing Machine", "Cardio", ["row erg", "erg row", "rower", "rowing", "erg", "cardio"], "cardio"),
    e("Stair Climber", "Cardio", ["stepmill", "stair climber", "cardio"], "cardio"),
    e("StairMaster", "Cardio", ["stair master", "stair climber", "cardio"], "cardio"),
    e("Ski Erg", "Cardio", ["ski machine", "ski erg", "cardio"], "cardio"),
    e("VersaClimber", "Cardio", ["vertical climber"], "cardio"),
    e("Jacob's Ladder", "Cardio", ["ladder climber"], "cardio"),
    e("Jump Rope", "Cardio", ["skipping"], "cardio"),
    e("Double-Under", "Cardio", ["double unders"], "cardio"),
    e("Battle Ropes", "Cardio", ["wave ropes"], "cardio"),
    e("Swimming", "Cardio", ["pool swim"], "cardio"),
    e("Open Water Swim", "Cardio", ["lake swim"], "cardio"),
    e("Rowing Erg Intervals", "Cardio", ["erg intervals"], "cardio"),
    e("Bike Erg", "Cardio", ["concept2 bike"], "cardio"),
    e("High Knees", "Cardio", ["running high knees"], "cardio"),
    e("Butt Kicks", "Cardio", ["heel kicks"], "cardio"),
    e("Shadow Boxing", "Cardio", ["boxing cardio"], "cardio"),
    e("Heavy Bag Work", "Cardio", ["punching bag"], "cardio"),
    e("Jumping Jack", "Cardio", ["star jump"], "cardio"),
    e("Box Step", "Cardio", ["step aerobics"], "cardio"),
    e("Hill Sprint", "Cardio", ["hill repeats"], "cardio"),
    e("Tempo Run", "Cardio", ["threshold run"], "cardio"),
    e("Interval Run", "Cardio", ["hiit run"], "cardio"),
    e("Rucking", "Cardio", ["weighted hike"], "cardio"),
    e("Hiking", "Cardio", ["trail hike"], "cardio"),
    e("Cross-Country Ski Erg", "Cardio", ["xc ski erg"], "cardio"),
    e("Pool Running", "Cardio", ["aqua jog"], "cardio"),
    e("Kickboxing", "Cardio", ["cardio kickboxing"], "cardio"),
    e("Dance Cardio", "Cardio", ["dance fitness"], "cardio"),
    e("Rowing Sprint", "Cardio", ["500m row"], "cardio"),
    e("Cycling Intervals", "Cardio", ["bike intervals"], "cardio"),
)

# ─── Full Body ─────────────────────────────────────────────────────────────────
add(
    e("Burpee", "Full Body", ["sprawl"], "bodyweight"),
    e("Burpee Box Jump", "Full Body", ["burpee to box"], "bodyweight"),
    e("Thruster", "Full Body", ["squat to press"]),
    e("Dumbbell Thruster", "Full Body", ["db thruster"]),
    e("Kettlebell Thruster", "Full Body", ["kb thruster"]),
    e("Kettlebell Swing", "Full Body", ["kb swing"]),
    e("American Kettlebell Swing", "Full Body", ["overhead kb swing"]),
    e("Russian Kettlebell Swing", "Full Body", ["eye level swing"]),
    e("Man Maker", "Full Body", ["dumbbell man maker"]),
    e("Devil Press", "Full Body", ["double db devil press"]),
    e("Dumbbell Snatch", "Full Body", ["single arm db snatch"]),
    e("Kettlebell Snatch", "Full Body", ["kb snatch"]),
    e("Dumbbell Clean", "Full Body", ["db clean"]),
    e("Kettlebell Clean", "Full Body", ["kb clean"]),
    e("Dumbbell Clean and Press", "Full Body", ["db clean press"]),
    e("Kettlebell Clean and Press", "Full Body", ["kb clean press"]),
    e("Farmer Carry", "Full Body", ["farmers walk"]),
    e("Suitcase Carry", "Full Body", ["single arm farmer"]),
    e("Overhead Carry", "Full Body", ["oh walk"]),
    e("Front Rack Carry", "Full Body", ["front rack walk"]),
    e("Zercher Carry", "Full Body", ["zercher walk"]),
    e("Yoke Walk", "Full Body", ["yoke carry"]),
    e("Sandbag Carry", "Full Body", ["bear hug carry"]),
    e("Atlas Stone Lift", "Full Body", ["stone lift"]),
    e("Tire Flip", "Full Body", ["tractor tire flip"]),
    e("Sled Push", "Full Body", ["prowler push"]),
    e("Sled Pull", "Full Body", ["backward drag"]),
    e("Wall Ball", "Full Body", ["wallball shot"]),
    e("Medicine Ball Clean", "Full Body", ["mb clean"]),
    e("Medicine Ball Throw", "Full Body", ["chest pass throw"]),
    e("Medicine Ball Rotational Throw", "Full Body", ["scoop throw"]),
    e("Bear Crawl", "Full Body", ["quadruped crawl"], "bodyweight"),
    e("Crab Walk", "Full Body", ["crab crawl"], "bodyweight"),
    e("Duck Walk", "Full Body", ["squat walk"]),
    e("Turkish Get-Up", "Full Body", ["tgu"]),
    e("Renegade Row to Press", "Full Body", ["row press complex"]),
    e("Clean and Press", "Full Body", ["barbell clean press"]),
    e("Hang Clean and Press", "Full Body", ["hang clean press"]),
    e("Rope Pull", "Full Body", ["sled rope pull"]),
    e("Sandbag Over Shoulder", "Full Body", ["bag toss"]),
    e("Sandbag Squat", "Full Body", ["bear hug squat"]),
    e("Sandbag Lunge", "Full Body", ["sandbag walking lunge"]),
    e("Med Ball Burpee", "Full Body", ["ball burpee"], "bodyweight"),
    e("Sprawl", "Full Body", ["mma sprawl"], "bodyweight"),
    e("Sprawl to Jump", "Full Body", ["sprawl jump"], "bodyweight"),
    e("Sprinter Start", "Full Body", ["explosive start"], "bodyweight"),
    e("Broad Jump", "Full Body", ["standing long jump"], "bodyweight"),
    e("Box Jump", "Full Body", ["plyometric box jump"], "bodyweight"),
    e("Depth Jump", "Full Body", ["reactive plyo jump"]),
    e("Clapping Push-Up", "Full Body", ["plyo push up"], "bodyweight"),
    e("Plyo Push-Up", "Full Body", ["explosive push up"], "bodyweight"),
    e("Battle Rope Wave", "Full Body", ["alternating waves"]),
    e("Resistance Band Squat Press", "Full Body", ["band thruster"]),
    e("Ring Muscle-Up", "Full Body", ["ring mu"], "bodyweight"),
    e("Bar Muscle-Up", "Full Body", ["bar mu"], "bodyweight"),
)

# ─── Olympic / Power ───────────────────────────────────────────────────────────
add(
    e("Clean", "Olympic / Power", ["full clean", "squat clean"]),
    e("Power Clean", "Olympic / Power", ["power clean from floor"]),
    e("Hang Clean", "Olympic / Power", ["hang clean"]),
    e("Hang Power Clean", "Olympic / Power", ["hang power clean"]),
    e("Clean Pull", "Olympic / Power", ["clean pull from floor"]),
    e("Clean High Pull", "Olympic / Power", ["clean high pull"]),
    e("Clean and Jerk", "Olympic / Power", ["c and j"]),
    e("Power Jerk", "Olympic / Power", ["power jerk"]),
    e("Split Jerk", "Olympic / Power", ["split jerk"]),
    e("Push Jerk", "Olympic / Power", ["push jerk"]),
    e("Snatch", "Olympic / Power", ["full snatch"]),
    e("Power Snatch", "Olympic / Power", ["power snatch from floor"]),
    e("Hang Snatch", "Olympic / Power", ["hang snatch"]),
    e("Hang Power Snatch", "Olympic / Power", ["hang power snatch"]),
    e("Snatch Pull", "Olympic / Power", ["snatch pull"]),
    e("Snatch High Pull", "Olympic / Power", ["snatch high pull"]),
    e("Muscle Snatch", "Olympic / Power", ["muscle snatch"]),
    e("Muscle Clean", "Olympic / Power", ["muscle clean"]),
    e("High Pull", "Olympic / Power", ["barbell high pull"]),
    e("Block Clean", "Olympic / Power", ["clean from blocks"]),
    e("Block Snatch", "Olympic / Power", ["snatch from blocks"]),
    e("Deficit Snatch", "Olympic / Power", ["snatch from deficit"]),
    e("Deficit Clean", "Olympic / Power", ["clean from deficit"]),
    e("Tall Clean", "Olympic / Power", ["tall clean drill"]),
    e("Tall Snatch", "Olympic / Power", ["tall snatch drill"]),
    e("Snatch Balance", "Olympic / Power", ["heaving snatch balance"]),
    e("Clean Grip Deadlift", "Olympic / Power", ["clean deadlift"]),
    e("Jerk Dip Squat", "Olympic / Power", ["jerk support squat"]),
    e("Jerk Recovery", "Olympic / Power", ["split recovery"]),
    e("Press in Snatch", "Olympic / Power", ["sots press"]),
    e("Snatch Push Press", "Olympic / Power", ["heaving snatch PP"]),
    e("Clean and Front Squat", "Olympic / Power", ["clean plus front squat"]),
    e("Snatch Pull Under", "Olympic / Power", ["pull under drill"]),
    e("Power Snatch from Blocks", "Olympic / Power", ["block power snatch"]),
    e("Power Clean from Blocks", "Olympic / Power", ["block power clean"]),
    e("Squat Jerk", "Olympic / Power", ["squat style jerk"]),
    e("Behind-the-Neck Jerk", "Olympic / Power", ["btnj"]),
    e("Snatch Deadlift", "Olympic / Power", ["first pull snatch"]),
    e("Clean Deadlift", "Olympic / Power", ["first pull clean"]),
    e("Segment Snatch", "Olympic / Power", ["paused snatch"]),
    e("Segment Clean", "Olympic / Power", ["paused clean"]),
    e("No-Feet Snatch", "Olympic / Power", ["no feet snatch drill"]),
    e("No-Feet Clean", "Olympic / Power", ["no feet clean drill"]),
    e("Hang Snatch Below Knee", "Olympic / Power", ["below knee snatch"]),
    e("Hang Clean Below Knee", "Olympic / Power", ["below knee clean"]),
    e("Snatch from Power Position", "Olympic / Power", ["hip snatch"]),
    e("Clean from Power Position", "Olympic / Power", ["hip clean"]),
    e("Jerk Drive", "Olympic / Power", ["jerk dip drive"]),
    e("Pin Squat", "Olympic / Power", ["anderson squat"]),
    e("Speed Deadlift", "Olympic / Power", ["dynamic effort deadlift"]),
    e("Speed Squat", "Olympic / Power", ["dynamic effort squat"]),
    e("Speed Bench", "Olympic / Power", ["dynamic effort bench"]),
    e("Band-Resisted Squat", "Olympic / Power", ["band squat"]),
    e("Chain Squat", "Olympic / Power", ["chain squat"]),
    e("Chain Bench Press", "Olympic / Power", ["chain bench"]),
    e("Reverse Band Bench", "Olympic / Power", ["reverse band bench"]),
    e("Slingshot Bench Press", "Olympic / Power", ["slingshot bench"]),
    e("Competition Bench Press", "Olympic / Power", ["powerlifting bench"]),
)

# ─── Mobility ────────────────────────────────────────────────────────────────────
add(
    e("World's Greatest Stretch", "Mobility", ["wgs", "worlds greatest stretch", "stretch", "mobility", "warm up", "hips"], "mobility"),
    e("Hip Flexor Stretch", "Mobility", ["kneeling hip flexor", "stretch", "mobility", "hips", "warm up"], "mobility"),
    e("Couch Stretch", "Mobility", ["quad couch stretch"], "mobility"),
    e("Hamstring Stretch", "Mobility", ["seated hamstring stretch"], "mobility"),
    e("Standing Hamstring Stretch", "Mobility", ["toe touch stretch"], "mobility"),
    e("Calf Stretch", "Mobility", ["wall calf stretch"], "mobility"),
    e("Adductor Rockback", "Mobility", ["groin rockback"], "mobility"),
    e("90-90 Hip Switch", "Mobility", ["shin box switch"], "mobility"),
    e("Pigeon Stretch", "Mobility", ["figure four stretch"], "mobility"),
    e("Thoracic Rotation", "Mobility", ["open book", "stretch", "mobility", "thoracic", "warm up"], "mobility"),
    e("Cat-Cow", "Mobility", ["cat cow", "stretch", "mobility", "warm up"], "mobility"),
    e("Shoulder Pass-Through", "Mobility", ["dowel pass through", "stretch", "mobility", "shoulders", "warm up"], "mobility"),
    e("Banded Shoulder External Rotation", "Mobility", ["band external rotation"], "mobility"),
    e("Banded Shoulder Internal Rotation", "Mobility", ["band internal rotation"], "mobility"),
    e("Ankle Dorsiflexion Drill", "Mobility", ["knee over toe"], "mobility"),
    e("Foam Roller Thoracic Extension", "Mobility", ["t spine roll"], "mobility"),
    e("Foam Roll Quadriceps", "Mobility", ["quad foam roll"], "mobility"),
    e("Foam Roll Hamstrings", "Mobility", ["hamstring roll"], "mobility"),
    e("Foam Roll IT Band", "Mobility", ["it band roll"], "mobility"),
    e("Foam Roll Calves", "Mobility", ["calf roll"], "mobility"),
    e("Foam Roll Lats", "Mobility", ["lat roll"], "mobility"),
    e("Lacrosse Ball Glute", "Mobility", ["glute smash"], "mobility"),
    e("Lacrosse Ball Pec", "Mobility", ["pec smash"], "mobility"),
    e("Wall Slide", "Mobility", ["scapular wall slide"], "mobility"),
    e("Quadruped Extension-Rotation", "Mobility", ["quad er"], "mobility"),
    e("Child's Pose", "Mobility", ["yoga childs pose"], "mobility"),
    e("Downward Dog", "Mobility", ["adho mukha"], "mobility"),
    e("Upward Dog", "Mobility", ["cobra stretch"], "mobility"),
    e("Thread the Needle", "Mobility", ["t spine thread"], "mobility"),
    e("Book Opener", "Mobility", ["lying t rotation"], "mobility"),
    e("Frog Stretch", "Mobility", ["groin frog"], "mobility"),
    e("Deep Squat Hold", "Mobility", ["asian squat hold"], "mobility"),
    e("Overhead Squat Hold", "Mobility", ["oh squat mobility"], "mobility"),
    e("Wrist Circles", "Mobility", ["wrist warmup"], "mobility"),
    e("Ankle Circles", "Mobility", ["ankle circles"], "mobility"),
    e("Hip Circles", "Mobility", ["hip CAR"], "mobility"),
    e("Shoulder CAR", "Mobility", ["shoulder CARs"], "mobility"),
    e("Neck CAR", "Mobility", ["neck controlled articular"], "mobility"),
    e("Scapular CAR", "Mobility", ["scap CAR"], "mobility"),
    e("Jefferson Curl", "Mobility", ["light jefferson curl"], "mobility"),
    e("Standing Forward Fold", "Mobility", ["toe touch hold"], "mobility"),
    e("Seated Forward Fold", "Mobility", ["pike stretch"], "mobility"),
    e("Figure-Four Stretch", "Mobility", ["seated figure four"], "mobility"),
    e("Supine Twist", "Mobility", ["lying spinal twist"], "mobility"),
    e("Happy Baby", "Mobility", ["yoga happy baby"], "mobility"),
    e("Puppy Pose", "Mobility", ["melting heart"], "mobility"),
    e("Lat Stretch", "Mobility", ["doorway lat stretch"], "mobility"),
    e("Doorway Pec Stretch", "Mobility", ["chest doorway stretch"], "mobility"),
    e("Cross-Body Shoulder Stretch", "Mobility", ["sleeper stretch prep"], "mobility"),
    e("Sleeper Stretch", "Mobility", ["posterior shoulder stretch"], "mobility"),
    e("W-ind Stretch", "Mobility", ["prone shoulder w"], "mobility"),
    e("Brettzel", "Mobility", ["side lying t spine"], "mobility"),
    e("Quadruped Rockback", "Mobility", ["child pose rockback"], "mobility"),
    e("Hip Airplane", "Mobility", ["single leg hip rotation"], "mobility"),
    e("Shin Box Switch", "Mobility", ["90 90 switch"], "mobility"),
    e("Lunge with Rotation", "Mobility", ["worlds greatest lunge"], "mobility"),
    e("Walking Spiderman", "Mobility", ["spiderman lunge"], "mobility"),
    e("Inchworm", "Mobility", ["walkout stretch"], "mobility"),
    e("Leg Swing Front", "Mobility", ["dynamic leg swing"], "mobility"),
    e("Leg Swing Lateral", "Mobility", ["lateral leg swing"], "mobility"),
    e("Arm Circle", "Mobility", ["shoulder circles"], "mobility"),
    e("Band Dislocate", "Mobility", ["band shoulder dislocate"], "mobility"),
    e("PVC Overhead Squat", "Mobility", ["pvc oh squat"], "mobility"),
    e("Wall Ankle Mobilization", "Mobility", ["wall ankle mob"], "mobility"),
    e("Calf Raise Stretch", "Mobility", ["eccentric calf stretch"], "mobility"),
    e("Tibialis Stretch", "Mobility", ["toe pull stretch"], "mobility"),
    e("QL Stretch", "Mobility", ["side bend stretch"], "mobility"),
    e("Prayer Stretch", "Mobility", ["child pose lat"], "mobility"),
    e("Scorpion Stretch", "Mobility", ["prone scorpion"], "mobility"),
    e("Cossack Mobility", "Mobility", ["cossack rock"], "mobility"),
    e("Deep Lunge Hold", "Mobility", ["hip flexor hold"], "mobility"),
    e("Supported Squat Hold", "Mobility", ["goblet squat hold"], "mobility"),
    e("Diaphragmatic Breathing", "Mobility", ["breathing drill"], "mobility"),
    e("Foam Roll Thoracic", "Mobility", ["upper back roll"], "mobility"),
    e("Stick Rollout", "Mobility", ["stick mobility"], "mobility"),
    e("Resistance Band Hip Distraction", "Mobility", ["banded hip distraction"], "mobility"),
    e("Banded Ankle Mobilization", "Mobility", ["band ankle mob"], "mobility"),
    e("Elevated Pigeon", "Mobility", ["box pigeon"], "mobility"),
    e("Standing Quad Stretch", "Mobility", ["flamingo stretch"], "mobility"),
    e("Lying Glute Stretch", "Mobility", ["supine glute stretch"], "mobility"),
    e("Seated Glute Stretch", "Mobility", ["chair glute stretch"], "mobility"),
    e("Overhead Triceps Stretch", "Mobility", ["triceps overhead stretch"], "mobility"),
    e("Cross-Body Triceps Stretch", "Mobility", ["triceps pull across"], "mobility"),
    e("Forearm Stretch", "Mobility", ["wrist flexor stretch"], "mobility"),
    e("Forearm Extensor Stretch", "Mobility", ["wrist extensor stretch"], "mobility"),
    e("Finger Extension Stretch", "Mobility", ["finger stretch"], "mobility"),
    e("Neck Stretch", "Mobility", ["gentle neck stretch"], "mobility"),
    e("Upper Trap Stretch", "Mobility", ["ear to shoulder stretch"], "mobility"),
    e("Levator Scapulae Stretch", "Mobility", ["levator stretch"], "mobility"),
    e("Dynamic Hip Flexor", "Mobility", ["walking hip flexor"], "mobility"),
    e("Dynamic Hamstring", "Mobility", ["walking hamstring"], "mobility"),
    e("Skip A", "Mobility", ["a skip warmup"], "mobility"),
    e("Skip B", "Mobility", ["b skip warmup"], "mobility"),
    e("Carioca", "Mobility", ["grapevine drill"], "mobility"),
    e("High Knee March", "Mobility", ["marching warmup"], "mobility"),
    e("Butt Kick March", "Mobility", ["heel to glute march"], "mobility"),
)

# Validate names before emitting generated Swift. Duplicate normalized names should
# be resolved in this source list, not silently dropped at generation time.
def norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", s.lower())

BLOCKED_NAMES = frozenset({
    "emom", "amrap", "tabata", "chipper",
    "barbellcomplex", "dumbbellcomplex", "kettlebellcomplex",
})

seen_by_key: dict[str, Exercise] = {}
unique: list[Exercise] = []
dupes: list[tuple[str, Exercise, Exercise]] = []
for ex in EXERCISES:
    key = norm(ex[0])
    if key in BLOCKED_NAMES:
        print(f"WARNING: blocked non-exercise name skipped: {ex[0]}")
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
    "Chest", "Back", "Shoulders", "Biceps", "Triceps", "Legs", "Glutes",
    "Core", "Cardio", "Full Body", "Olympic / Power", "Mobility",
]

by_cat: dict[str, list[Exercise]] = {c: [] for c in SECTION_ORDER}
for ex in unique:
    cat = ex[1]
    if cat not in by_cat:
        raise ValueError(f"Unknown category: {cat} for {ex[0]}")
    by_cat[cat].append(ex)

for cat in SECTION_ORDER:
    print(f"  {cat}: {len(by_cat[cat])}")

def swift_aliases(aliases: list[str]) -> str:
    if not aliases:
        return "[]"
    parts = ", ".join(f'"{a.replace(chr(92), chr(92)+chr(92)).replace(chr(34), chr(92)+chr(34))}"' for a in aliases)
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
    '        _ name: String,',
    '        _ category: String,',
    '        _ aliases: [String],',
    "        _ loggingType: ExerciseLoggingType = .strength",
    "    ) -> (name: String, category: String, aliases: [String], loggingType: ExerciseLoggingType) {",
    "        (name, category, aliases, loggingType)",
    "    }",
    "",
    "    // Keep this list hand-editable. `category` is treated as muscle group.",
    "    static let items: [(name: String, category: String, aliases: [String], loggingType: ExerciseLoggingType)] = [",
]

for cat in SECTION_ORDER:
    lines.append(f"        // {cat}")
    for ex in by_cat[cat]:
        lines.append(swift_row(ex))
    lines.append("")

# remove trailing blank before closing
if lines[-1] == "":
    lines.pop()
lines[-1] = lines[-1].rstrip(",")  # last row shouldn't have been changed
# fix: last item needs comma removed only on final row of array
# Actually all rows should have commas except we need proper Swift - trailing comma is OK in Swift

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
