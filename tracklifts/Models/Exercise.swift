//
//  Exercise.swift
//  tracklifts
//

import Foundation
import SwiftData

/// A single exercise in the library (seeded or user-created).
@Model
final class Exercise {
    var name: String = ""
    /// Raw value of `MuscleGroup`. Stored as a string for reliable predicates.
    var muscleGroupRaw: String = MuscleGroup.chest.rawValue
    var isFavorite: Bool = false
    /// True for exercises the user added themselves (deletable / editable).
    var isCustom: Bool = false
    /// A calisthenic movement loaded by body weight (pull-up, sit-up, dip…).
    /// Logged sets record reps and *added* weight (0 = pure bodyweight).
    var isBodyweight: Bool = false
    var notes: String = ""
    var createdAt: Date = Date()

    init(
        name: String,
        muscleGroup: MuscleGroup,
        isFavorite: Bool = false,
        isCustom: Bool = false,
        isBodyweight: Bool = false,
        notes: String = ""
    ) {
        self.name = name
        self.muscleGroupRaw = muscleGroup.rawValue
        self.isFavorite = isFavorite
        self.isCustom = isCustom
        self.isBodyweight = isBodyweight
        self.notes = notes
        self.createdAt = Date()
    }

    var muscleGroup: MuscleGroup {
        get { MuscleGroup(rawValue: muscleGroupRaw) ?? .chest }
        set { muscleGroupRaw = newValue.rawValue }
    }
}
