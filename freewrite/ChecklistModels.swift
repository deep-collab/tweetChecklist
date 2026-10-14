import Foundation
import SwiftUI

// MARK: - Requirement Item
struct ChecklistRequirement: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var guidance: String
    var tag: String
    var template: String? = nil
    var isChecked: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, title, guidance, tag, template
    }

    init(id: UUID = UUID(), title: String, guidance: String, tag: String, template: String? = nil, isChecked: Bool = false) {
        self.id = id
        self.title = title
        self.guidance = guidance
        self.tag = tag
        self.template = template
        self.isChecked = isChecked
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.title = try container.decode(String.self, forKey: .title)
        self.guidance = try container.decodeIfPresent(String.self, forKey: .guidance) ?? ""
        self.tag = try container.decodeIfPresent(String.self, forKey: .tag) ?? "General"
        self.template = try container.decodeIfPresent(String.self, forKey: .template)
        self.isChecked = false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(guidance, forKey: .guidance)
        try container.encode(tag, forKey: .tag)
        try container.encodeIfPresent(template, forKey: .template)
    }
}

// MARK: - Post Strategy
struct ContentStrategy: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var emoji: String
    var description: String
    var items: [ChecklistRequirement]

    enum CodingKeys: String, CodingKey {
        case id, name, emoji, description, items
    }

    init(id: UUID = UUID(), name: String, emoji: String, description: String, items: [ChecklistRequirement]) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.description = description
        self.items = items
    }
}
