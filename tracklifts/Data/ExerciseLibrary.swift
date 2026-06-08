//
//  ExerciseLibrary.swift
//  tracklifts
//
//  The default exercise catalog seeded on first launch.
//

import Foundation

enum ExerciseLibrary {
    /// (name, muscleGroup) pairs for every seeded exercise.
    static let all: [(String, MuscleGroup)] = chest + back + shoulders + biceps + triceps + legs + core

    /// Seeded movements loaded by body weight. Their logged sets record reps and
    /// *added* weight (0 = pure bodyweight) rather than an external load.
    static let bodyweight: Set<String> = [
        "Push-Up", "Dips (Chest)",
        "Pull-Up", "Chin-Up", "Back Extension",
        "Dips (Triceps)", "Bench Dip",
        "Plank", "Hanging Leg Raise", "Russian Twist",
        "Ab Wheel Rollout", "Decline Sit-Up", "Mountain Climber",
    ]

    static func isBodyweight(_ name: String) -> Bool { bodyweight.contains(name) }

    static let chest: [(String, MuscleGroup)] = [
        ("Barbell Bench Press", .chest),
        ("Incline Barbell Bench Press", .chest),
        ("Dumbbell Bench Press", .chest),
        ("Incline Dumbbell Press", .chest),
        ("Decline Bench Press", .chest),
        ("Machine Chest Press", .chest),
        ("Pec Deck Fly", .chest),
        ("Cable Crossover", .chest),
        ("Dumbbell Fly", .chest),
        ("Push-Up", .chest),
        ("Dips (Chest)", .chest),
    ]

    static let back: [(String, MuscleGroup)] = [
        ("Deadlift", .back),
        ("Pull-Up", .back),
        ("Chin-Up", .back),
        ("Lat Pulldown", .back),
        ("Barbell Row", .back),
        ("Bent-Over Dumbbell Row", .back),
        ("Seated Cable Row", .back),
        ("T-Bar Row", .back),
        ("Single-Arm Dumbbell Row", .back),
        ("Straight-Arm Pulldown", .back),
        ("Face Pull", .back),
        ("Back Extension", .back),
    ]

    static let shoulders: [(String, MuscleGroup)] = [
        ("Overhead Barbell Press", .shoulders),
        ("Seated Dumbbell Shoulder Press", .shoulders),
        ("Arnold Press", .shoulders),
        ("Lateral Raise", .shoulders),
        ("Front Raise", .shoulders),
        ("Rear Delt Fly", .shoulders),
        ("Cable Lateral Raise", .shoulders),
        ("Upright Row", .shoulders),
        ("Barbell Shrug", .shoulders),
    ]

    static let biceps: [(String, MuscleGroup)] = [
        ("Barbell Curl", .biceps),
        ("Dumbbell Curl", .biceps),
        ("Hammer Curl", .biceps),
        ("Preacher Curl", .biceps),
        ("Incline Dumbbell Curl", .biceps),
        ("Cable Curl", .biceps),
        ("Concentration Curl", .biceps),
        ("EZ-Bar Curl", .biceps),
    ]

    static let triceps: [(String, MuscleGroup)] = [
        ("Close-Grip Bench Press", .triceps),
        ("Triceps Pushdown", .triceps),
        ("Overhead Triceps Extension", .triceps),
        ("Skull Crusher", .triceps),
        ("Dips (Triceps)", .triceps),
        ("Triceps Kickback", .triceps),
        ("Rope Pushdown", .triceps),
        ("Bench Dip", .triceps),
    ]

    static let legs: [(String, MuscleGroup)] = [
        ("Barbell Back Squat", .legs),
        ("Front Squat", .legs),
        ("Leg Press", .legs),
        ("Romanian Deadlift", .legs),
        ("Bulgarian Split Squat", .legs),
        ("Walking Lunge", .legs),
        ("Leg Extension", .legs),
        ("Lying Leg Curl", .legs),
        ("Seated Leg Curl", .legs),
        ("Hip Thrust", .legs),
        ("Standing Calf Raise", .legs),
        ("Seated Calf Raise", .legs),
        ("Goblet Squat", .legs),
        ("Hack Squat", .legs),
    ]

    static let core: [(String, MuscleGroup)] = [
        ("Plank", .core),
        ("Hanging Leg Raise", .core),
        ("Cable Crunch", .core),
        ("Russian Twist", .core),
        ("Ab Wheel Rollout", .core),
        ("Decline Sit-Up", .core),
        ("Mountain Climber", .core),
    ]
}
