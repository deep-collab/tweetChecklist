import Foundation
import SwiftUI
import Combine

class ChecklistManager: ObservableObject {
    static let shared = ChecklistManager()

    @Published var strategies: [ContentStrategy] = []
    @Published var activeStrategyId: UUID? = nil
    @Published var selectedTagFilter: String = "All"
    @Published var checkedItemIds: Set<UUID> = []

    private let saveURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let freewriteDir = docs.appendingPathComponent("Freewrite")
        try? FileManager.default.createDirectory(at: freewriteDir, withIntermediateDirectories: true)
        self.saveURL = freewriteDir.appendingPathComponent("twitter_checklists.json")

        loadStrategies()
    }

    var activeStrategy: ContentStrategy? {
        if let id = activeStrategyId, let strat = strategies.first(where: { $0.id == id }) {
            return strat
        }
        let fallback = strategies.first
        if activeStrategyId != fallback?.id {
            DispatchQueue.main.async {
                self.activeStrategyId = fallback?.id
            }
        }
        return fallback
    }

    var activeStrategyIndex: Int? {
        guard let active = activeStrategy else { return nil }
        return strategies.firstIndex(where: { $0.id == active.id })
    }

    func isItemChecked(_ itemId: UUID) -> Bool {
        checkedItemIds.contains(itemId)
    }

    func toggleCheck(itemId: UUID) {
        objectWillChange.send()
        if checkedItemIds.contains(itemId) {
            checkedItemIds.remove(itemId)
        } else {
            checkedItemIds.insert(itemId)
        }
    }

    func resetChecks() {
        objectWillChange.send()
        checkedItemIds.removeAll()
    }

    func markAllCompleted() {
        objectWillChange.send()
        guard let strat = activeStrategy else { return }
        for item in strat.items {
            checkedItemIds.insert(item.id)
        }
    }

    func addRequirement(to strategyId: UUID, title: String, guidance: String, tag: String, template: String? = nil) {
        guard let stratIdx = strategies.firstIndex(where: { $0.id == strategyId }) else { return }
        objectWillChange.send()
        let cleanTag = tag.trimmingCharacters(in: .whitespaces).isEmpty ? "General" : tag
        let cleanTemplate = template?.trimmingCharacters(in: .whitespaces).isEmpty == true ? nil : template
        let newItem = ChecklistRequirement(title: title, guidance: guidance, tag: cleanTag, template: cleanTemplate)
        strategies[stratIdx].items.append(newItem)
        saveStrategies()
    }

    func updateRequirement(strategyId: UUID, itemId: UUID, title: String, guidance: String, tag: String, template: String? = nil) {
        guard let stratIdx = strategies.firstIndex(where: { $0.id == strategyId }),
              let itemIdx = strategies[stratIdx].items.firstIndex(where: { $0.id == itemId }) else { return }
        objectWillChange.send()
        let cleanTag = tag.trimmingCharacters(in: .whitespaces).isEmpty ? "General" : tag
        let cleanTemplate = template?.trimmingCharacters(in: .whitespaces).isEmpty == true ? nil : template
        strategies[stratIdx].items[itemIdx].title = title
        strategies[stratIdx].items[itemIdx].guidance = guidance
        strategies[stratIdx].items[itemIdx].tag = cleanTag
        strategies[stratIdx].items[itemIdx].template = cleanTemplate
        saveStrategies()
    }

    func deleteRequirement(strategyId: UUID, itemId: UUID) {
        guard let stratIdx = strategies.firstIndex(where: { $0.id == strategyId }) else { return }
        objectWillChange.send()
        strategies[stratIdx].items.removeAll(where: { $0.id == itemId })
        checkedItemIds.remove(itemId)
        saveStrategies()
    }

    func addStrategy(name: String, emoji: String, description: String, initialItems: [ChecklistRequirement]? = nil) {
        objectWillChange.send()
        let defaultItems = starterMultiCategoryItems()

        let newStrat = ContentStrategy(
            name: name,
            emoji: emoji.trimmingCharacters(in: .whitespaces).isEmpty ? "📌" : emoji.trimmingCharacters(in: .whitespaces),
            description: description,
            items: initialItems ?? defaultItems
        )
        strategies.append(newStrat)
        activeStrategyId = newStrat.id
        saveStrategies()
    }

    func updateStrategy(id: UUID, name: String, emoji: String, description: String) {
        guard let idx = strategies.firstIndex(where: { $0.id == id }) else { return }
        objectWillChange.send()
        strategies[idx].name = name
        strategies[idx].emoji = emoji.trimmingCharacters(in: .whitespaces).isEmpty ? "📌" : emoji.trimmingCharacters(in: .whitespaces)
        strategies[idx].description = description
        saveStrategies()
    }

    func deleteStrategy(id: UUID) {
        guard strategies.count > 1 else { return } // Keep at least one
        objectWillChange.send()
        strategies.removeAll(where: { $0.id == id })
        if activeStrategyId == id {
            activeStrategyId = strategies.first?.id
        }
        saveStrategies()
    }

    func restoreDefaultStrategies() {
        objectWillChange.send()
        self.strategies = defaultStrategies()
        self.activeStrategyId = strategies.first?.id
        saveStrategies()
    }

    private func saveStrategies() {
        do {
            let data = try JSONEncoder().encode(strategies)
            try data.write(to: saveURL)
        } catch {
            print("Failed to save checklists: \(error)")
        }
    }

    private func loadStrategies() {
        if FileManager.default.fileExists(atPath: saveURL.path),
           let data = try? Data(contentsOf: saveURL),
           let decoded = try? JSONDecoder().decode([ContentStrategy].self, from: data),
           !decoded.isEmpty {
            self.strategies = decoded
            
            // Check if Controversial Take needs enrichment to full multi-category specification
            var needsSave = false
            for (idx, strat) in strategies.enumerated() {
                if strat.name.lowercased().contains("controversial") && strat.items.count < 15 {
                    if let defaultControversial = defaultStrategies().first(where: { $0.name.lowercased().contains("controversial") }) {
                        strategies[idx].items = defaultControversial.items
                        needsSave = true
                    }
                }
            }
            
            self.activeStrategyId = decoded.first?.id
            if needsSave {
                saveStrategies()
            }
            return
        }

        // Default strategies
        self.strategies = defaultStrategies()
        self.activeStrategyId = strategies.first?.id
        saveStrategies()
    }

    private func starterMultiCategoryItems() -> [ChecklistRequirement] {
        return [
            ChecklistRequirement(title: "The Pattern Interrupt Hook", guidance: "Grab the reader in the first 80 characters.", tag: "Hook", template: "Most people think [A]. The top 1% know [B]:"),
            ChecklistRequirement(title: "The Contrarian Hook", guidance: "Challenge popular consensus directly.", tag: "Hook", template: "Unpopular truth about [topic]:"),
            ChecklistRequirement(title: "High-Contrast Sentences", guidance: "Keep sentences punchy and cut filler words.", tag: "Writing"),
            ChecklistRequirement(title: "Steelman Opposing View", guidance: "Acknowledge the sensible counter-argument before debunking it.", tag: "Writing"),
            ChecklistRequirement(title: "Concrete Receipts & Proof", guidance: "Include real metrics, screenshots, or personal data.", tag: "Implementing", template: "Here are the exact metrics after [X days]:"),
            ChecklistRequirement(title: "Step-by-Step Replacement", guidance: "Provide actionable alternative steps (1, 2, 3).", tag: "Implementing"),
            ChecklistRequirement(title: "Open Debate CTA", guidance: "Ask where readers stand to trigger active replies.", tag: "CTA", template: "Where do you stand on this? Tell me below."),
            ChecklistRequirement(title: "Bookmark CTA", guidance: "Remind readers to save for future reference.", tag: "CTA", template: "Bookmark this before you make this mistake.")
        ]
    }

    func defaultStrategies() -> [ContentStrategy] {
        return [
            // 1. Controversial Take (with 10 hooks, 5 writing, 5 implementing, 5 CTA)
            ContentStrategy(
                name: "Controversial Take",
                emoji: "🔥",
                description: "Polarizing perspective with strong justification to ignite comments and debate.",
                items: [
                    // HOOKS (10 kinds)
                    ChecklistRequirement(
                        title: "The 'X is Dead' Disruptor",
                        guidance: "Only declare something dead if you provide a superior alternative immediately.",
                        tag: "Hook",
                        template: "[Common practice] is dead. Here is what is replacing it in 2026:"
                    ),
                    ChecklistRequirement(
                        title: "The Harsh Truth / Reality Check",
                        guidance: "Articulate a widely felt frustration or taboo truth that people hesitate to speak.",
                        tag: "Hook",
                        template: "Unpopular opinion: [Hard truth that 90% of people avoid admitting]."
                    ),
                    ChecklistRequirement(
                        title: "The Counter-Intuitive Reversal",
                        guidance: "Flip standard advice on its head with counter-intuitive logic.",
                        tag: "Hook",
                        template: "Doing [common advice] is the exact reason you are failing at [goal]. Do this instead:"
                    ),
                    ChecklistRequirement(
                        title: "The 'Stop Doing X' Warning",
                        guidance: "Creates intense urgency and loss aversion by calling out an active mistake.",
                        tag: "Hook",
                        template: "Stop doing [common behavior] in 2026. It's secretly destroying your [result]."
                    ),
                    ChecklistRequirement(
                        title: "The Industry Call-Out",
                        guidance: "Breaks the fourth wall and establishes insider authority by exposing industry secrets.",
                        tag: "Hook",
                        template: "I'm going to say what most [founders/experts] won't say publicly:"
                    ),
                    ChecklistRequirement(
                        title: "The Bold Contrarian Claim",
                        guidance: "Contrasts herd mentality with what top 1% practitioners actually do.",
                        tag: "Hook",
                        template: "Everyone is hyping [popular trend], but 99% of people are missing the real trap:"
                    ),
                    ChecklistRequirement(
                        title: "The Shocking Metric Disconnect",
                        guidance: "Use hard contrasting numbers to break mental patterns and create dissonance.",
                        tag: "Hook",
                        template: "[90]% of people spend hours on [X]. It only drives [5]% of results. Here is what actually moves the needle:"
                    ),
                    ChecklistRequirement(
                        title: "The Anti-Advice Hook",
                        guidance: "Uses personal scar tissue and cautionary framing against bad mainstream guidance.",
                        tag: "Hook",
                        template: "The worst advice I ever received was '[popular adage]'. Here is why following it cost me [time/money]:"
                    ),
                    ChecklistRequirement(
                        title: "The Paradox / Irony Hook",
                        guidance: "Frames the problem as a psychological paradox where trying harder makes things worse.",
                        tag: "Hook",
                        template: "The harder you chase [result], the further away it gets. The paradox of [topic]:"
                    ),
                    ChecklistRequirement(
                        title: "The Dramatic Prediction",
                        guidance: "Forces immediate self-evaluation by setting a ticking clock on obsolete habits.",
                        tag: "Hook",
                        template: "In 12 months, [industry/skill] won't look anything like today. If you aren't doing [X], you're already behind:"
                    ),

                    // WRITING (5 kinds)
                    ChecklistRequirement(
                        title: "Steelman Counter-Argument",
                        guidance: "Acknowledge the sensible opposing viewpoint in 1 sentence before debunking it.",
                        tag: "Writing",
                        template: "I get why people advocate for [opposing view]. It works if [niche scenario]. But for everyone else:"
                    ),
                    ChecklistRequirement(
                        title: "High-Contrast Sentences",
                        guidance: "Cut filler words. Alternate 3-word punchy sentences with short, tight explanations.",
                        tag: "Writing",
                        template: "Most focus on volume. The best focus on leverage."
                    ),
                    ChecklistRequirement(
                        title: "The Isolated 1-Line Truth",
                        guidance: "Put your core thesis on its own line surrounded by whitespace for maximum psychological impact.",
                        tag: "Writing",
                        template: "If it doesn't hurt your ego a little bit, it's not a real insight."
                    ),
                    ChecklistRequirement(
                        title: "Zero-Hedging Tone",
                        guidance: "Remove weak phrases like 'I think', 'maybe', 'in my opinion'. Speak with grounded conviction.",
                        tag: "Writing",
                        template: "Cut 'I think' and 'maybe'. State your thesis directly."
                    ),
                    ChecklistRequirement(
                        title: "Tension Before Resolution",
                        guidance: "Hold back the full solution until the middle of the post to maximize read-through rate.",
                        tag: "Writing",
                        template: "Don't resolve the mystery in the first 2 lines. Keep them reading to line 4."
                    ),

                    // IMPLEMENTING (5 kinds)
                    ChecklistRequirement(
                        title: "Concrete Receipts & Proof",
                        guidance: "Back up controversial claims with real screenshots, benchmarks, case studies, or hard numbers.",
                        tag: "Implementing",
                        template: "Here are the exact numbers from testing this over [timeframe]:"
                    ),
                    ChecklistRequirement(
                        title: "3-Step Replacement Playbook",
                        guidance: "Don't just criticize the status quo; give a concrete, actionable alternative system.",
                        tag: "Implementing",
                        template: "Step 1: [Action]\nStep 2: [Action]\nStep 3: [Action]"
                    ),
                    ChecklistRequirement(
                        title: "The Boundary Exception Clause",
                        guidance: "Explicitly clarify when your take DOES NOT apply to protect against cheap nitpicking.",
                        tag: "Implementing",
                        template: "(Note: this does not apply if you are [specific scenario].)"
                    ),
                    ChecklistRequirement(
                        title: "Before vs After Delta",
                        guidance: "Contrast the old flawed way with the new optimized outcome side-by-side.",
                        tag: "Implementing",
                        template: "Old way: [Effort] -> [Poor result]\nNew way: [Smart effort] -> [10x result]"
                    ),
                    ChecklistRequirement(
                        title: "15-Minute Actionable Test",
                        guidance: "Give the reader 1 micro-action they can test today to verify your claim themselves.",
                        tag: "Implementing",
                        template: "Try this for 15 minutes today: [Specific test]. See the difference yourself."
                    ),

                    // CTA (5 kinds)
                    ChecklistRequirement(
                        title: "The Open Debate Question",
                        guidance: "Ask an open question that forces readers to pick a side in the comments.",
                        tag: "CTA",
                        template: "Where do you stand on this? Agree or disagree? Tell me below."
                    ),
                    ChecklistRequirement(
                        title: "The 'Prove Me Wrong' Challenge",
                        guidance: "Invites critical minds and experts to engage in constructive debate.",
                        tag: "CTA",
                        template: "Change my mind. Tell me where this thesis breaks down in the replies."
                    ),
                    ChecklistRequirement(
                        title: "The Bookmark Reality Check",
                        guidance: "Remind readers to save/bookmark this post for reference when they face this situation.",
                        tag: "CTA",
                        template: "Bookmark this to revisit before you make this costly mistake again."
                    ),
                    ChecklistRequirement(
                        title: "The Quote-Tweet Trigger",
                        guidance: "Prompt quote tweets to tap into second-degree audiences.",
                        tag: "CTA",
                        template: "Quote-tweet this with your most controversial belief on [topic]."
                    ),
                    ChecklistRequirement(
                        title: "Unfiltered Follow Prompt",
                        guidance: "Convert impressed readers into followers by promising more no-BS insights.",
                        tag: "CTA",
                        template: "If you want raw, unfiltered lessons on [topic], follow for daily breakdowns."
                    )
                ]
            ),

            // 2. Educational Breakdown
            ContentStrategy(
                name: "Educational Breakdown",
                emoji: "📚",
                description: "Actionable step-by-step breakdown or framework that earns instant bookmarks.",
                items: [
                    // Hooks
                    ChecklistRequirement(title: "Concrete ROI Promise Hook", guidance: "Specify the exact outcome: 'How to save 4 hours/day with X'.", tag: "Hook", template: "How to [achieve dream outcome] in [timeframe] without [annoying sacrifice]:"),
                    ChecklistRequirement(title: "The Curated Masterclass Hook", guidance: "Frame years of learning into a 2-minute masterclass.", tag: "Hook", template: "I spent 5 years studying [skill]. Here are the 5 frameworks that actually matter:"),
                    ChecklistRequirement(title: "The Cheat Sheet Hook", guidance: "Offer a high-density reference guide.", tag: "Hook", template: "The ultimate cheat sheet for [goal] (save this for later):"),
                    ChecklistRequirement(title: "The Beginner vs Pro Hook", guidance: "Contrast amateur mistakes with professional workflows.", tag: "Hook", template: "Beginners focus on [X]. Pros focus on [Y]. The breakdown:"),
                    ChecklistRequirement(title: "The Teardown Hook", guidance: "Deep-dive analyze a recognized winning example.", tag: "Hook", template: "A teardown of how [Company/Creator] generated [Result] with zero ad spend:"),

                    // Writing
                    ChecklistRequirement(title: "Numbered Steps & Bullet Points", guidance: "Break down into 3-5 scannable points.", tag: "Writing"),
                    ChecklistRequirement(title: "Simple Analogies for Complex Concepts", guidance: "Use everyday metaphors to make technical ideas click.", tag: "Writing"),
                    ChecklistRequirement(title: "High Signal-to-Noise Formatting", guidance: "Bold key takeaways and use line breaks between concepts.", tag: "Writing"),
                    ChecklistRequirement(title: "Action Verbs First", guidance: "Start every numbered point with an imperative verb (Build, Test, Cut).", tag: "Writing"),
                    ChecklistRequirement(title: "Executive Summary / TL;DR", guidance: "Include a 1-sentence summary at the top or bottom.", tag: "Writing"),

                    // Implementing
                    ChecklistRequirement(title: "Copy-Paste Ready Template", guidance: "Provide exact text or prompt the reader can copy.", tag: "Implementing", template: "Copy-paste this exact prompt/template:\n\"[Insert template]\""),
                    ChecklistRequirement(title: "Real Before & After Example", guidance: "Show actual numbers or screenshots of the workflow in action.", tag: "Implementing"),
                    ChecklistRequirement(title: "Tool & Resource Recommendations", guidance: "List the free or paid tools needed to execute.", tag: "Implementing"),
                    ChecklistRequirement(title: "Common Pitfalls & Fixes", guidance: "Warn readers about the #1 mistake people make when executing.", tag: "Implementing"),
                    ChecklistRequirement(title: "Day 1 Action Checklist", guidance: "Give readers the exact first step to take in under 5 minutes.", tag: "Implementing"),

                    // CTA
                    ChecklistRequirement(title: "Bookmark & Reference CTA", guidance: "Remind readers to save for later.", tag: "CTA", template: "Bookmark this breakdown so you can refer back when building."),
                    ChecklistRequirement(title: "Repost for Your Network", guidance: "Encourage sharing with peers.", tag: "CTA", template: "Repost this to help another builder in your network."),
                    ChecklistRequirement(title: "Ask a Question CTA", guidance: "Prompt readers to ask about their specific use case.", tag: "CTA", template: "Have questions about applying this to your stack? Drop them below."),
                    ChecklistRequirement(title: "Follow for Daily Frameworks", guidance: "Invite follows with a specific content value proposition.", tag: "CTA", template: "Follow @handle for actionable systems breakdowns every week."),
                    ChecklistRequirement(title: "Deep-Dive Link / Guide CTA", guidance: "Direct readers to full guide or newsletter.", tag: "CTA", template: "Want the full in-depth checklist? Link in bio.")
                ]
            ),

            // 3. Launch / Announcement
            ContentStrategy(
                name: "Launch / Announcement",
                emoji: "🚀",
                description: "Product, feature, or project reveal highlighting the problem it solves.",
                items: [
                    // Hooks
                    ChecklistRequirement(title: "Lead with the Pain Point", guidance: "Start with the painful problem your product solves, not just 'I launched X'.", tag: "Hook", template: "Building [product] was a nightmare because of [pain]. So we built [solution]:"),
                    ChecklistRequirement(title: "The 'After X Months of Building' Hook", guidance: "Share the journey timeline to highlight dedication.", tag: "Hook", template: "After 6 months of private testing with 500 users, [Product] is finally live:"),
                    ChecklistRequirement(title: "The '10x Faster' Promise Hook", guidance: "Highlight the speed or cost breakthrough.", tag: "Hook", template: "What used to take 3 hours now takes 30 seconds. Introducing [Product]:"),
                    ChecklistRequirement(title: "The Demo GIF / Video Hook", guidance: "Point directly to the attached visual demo.", tag: "Hook", template: "Watch this 30-second demo of how [Feature] works:"),
                    ChecklistRequirement(title: "The Free Tier / Open Access Hook", guidance: "Highlight immediate frictionless access.", tag: "Hook", template: "We just made [Tool] 100% free and open to everyone starting today:"),

                    // Writing
                    ChecklistRequirement(title: "Feature-to-Benefit Translation", guidance: "Explain what each feature allows the user to achieve.", tag: "Writing"),
                    ChecklistRequirement(title: "Brevity & High Scannability", guidance: "Keep sentences short and punchy so excitement builds.", tag: "Writing"),
                    ChecklistRequirement(title: "Social Proof Early", guidance: "Mention beta users, waiting list count, or testimonials.", tag: "Writing"),
                    ChecklistRequirement(title: "Transparent Pricing", guidance: "Be clear on free vs paid without hiding behind sales calls.", tag: "Writing"),
                    ChecklistRequirement(title: "Founder Gratitude", guidance: "Briefly thank the early community or beta testers.", tag: "Writing"),

                    // Implementing
                    ChecklistRequirement(title: "1-Click Direct Link", guidance: "Put the link cleanly with clear expectations of what they'll find.", tag: "Implementing", template: "Try it out here: [Link] (no credit card required)"),
                    ChecklistRequirement(title: "Demo Video or GIF Attached", guidance: "Ensure visual proof is attached to the post.", tag: "Implementing"),
                    ChecklistRequirement(title: "Early Bird / Launch Offer", guidance: "Add limited-time launch bonus or discount.", tag: "Implementing"),
                    ChecklistRequirement(title: "Quick FAQ in Thread", guidance: "Answer top 2 questions in the immediate reply.", tag: "Implementing"),
                    ChecklistRequirement(title: "Roadmap Teaser", guidance: "Give a hint of what is coming in version 2.0.", tag: "Implementing"),

                    // CTA
                    ChecklistRequirement(title: "Direct Try It CTA", guidance: "Clear call to action to test the product.", tag: "CTA", template: "Give it a spin today and let me know what you think: [Link]"),
                    ChecklistRequirement(title: "Feedback Request CTA", guidance: "Ask for honest critical feedback.", tag: "CTA", template: "We are actively iterating — drop your harshest feedback below."),
                    ChecklistRequirement(title: "Repost for Launch Support CTA", guidance: "Ask community to support the launch.", tag: "CTA", template: "A repost to support an indie builder means the world! 🚀"),
                    ChecklistRequirement(title: "DM for Access / Promo Code", guidance: "Encourage DMs for higher algorithmic engagement.", tag: "CTA", template: "DM me 'ACCESS' and I'll send you an extended pro trial."),
                    ChecklistRequirement(title: "Join the Community CTA", guidance: "Invite into Discord, Slack, or email list.", tag: "CTA", template: "Join 1,000+ builders in our community: [Link]")
                ]
            ),

            // 4. Personal Story & Lesson
            ContentStrategy(
                name: "Personal Story & Lesson",
                emoji: "💡",
                description: "Authentic founder/creator journey with vulnerability and hard-won takeaways.",
                items: [
                    // Hooks
                    ChecklistRequirement(title: "Vulnerable Opening Line", guidance: "Hook with the low point or dramatic turning point.", tag: "Hook", template: "In 2021, I had $400 left in my bank account and zero clients. Here is what changed:"),
                    ChecklistRequirement(title: "The Costly Mistake Hook", guidance: "Lead with how much money or time a mistake cost.", tag: "Hook", template: "I lost $50,000 making this 1 mistake as a first-time founder:"),
                    ChecklistRequirement(title: "The Counter-Intuitive Turning Point", guidance: "Hook with the counter-intuitive decision that paid off.", tag: "Hook", template: "Everyone told me quitting [job/path] was reckless. 2 years later:"),
                    ChecklistRequirement(title: "The 'Letter to My Younger Self' Hook", guidance: "Frame as wisdom you wish you had known earlier.", tag: "Hook", template: "If I could start over from scratch at age 20, here is the exact roadmap I'd follow:"),
                    ChecklistRequirement(title: "The Hard Reality Shock Hook", guidance: "Hook with a raw moment of realization.", tag: "Hook", template: "It took burning out twice for me to realize this brutal truth about productivity:"),

                    // Writing
                    ChecklistRequirement(title: "Show, Don't Just Tell", guidance: "Describe physical details or emotional moments.", tag: "Writing"),
                    ChecklistRequirement(title: "Conversational Cadence", guidance: "Write like you're talking to a close friend over coffee.", tag: "Writing"),
                    ChecklistRequirement(title: "The Pivotal Realization Moment", guidance: "Make the turning point crystal clear to the reader.", tag: "Writing"),
                    ChecklistRequirement(title: "Humility and Self-Awareness", guidance: "Avoid humblebrags; stay grounded and relatable.", tag: "Writing"),
                    ChecklistRequirement(title: "Pacing & Short Paragraphs", guidance: "Use white space so the emotional beats land effectively.", tag: "Writing"),

                    // Implementing
                    ChecklistRequirement(title: "Actionable Moral / Takeaway", guidance: "Extract the 1 lesson readers can apply today.", tag: "Implementing", template: "The single lesson: [Actionable rule]."),
                    ChecklistRequirement(title: "Daily Habit Shift", guidance: "Share the specific routine change that sustained the progress.", tag: "Implementing"),
                    ChecklistRequirement(title: "Recommended Book / Resource", guidance: "Mention the resource that sparked the turning point.", tag: "Implementing"),
                    ChecklistRequirement(title: "Framework from the Pain", guidance: "Turn the painful lesson into a reusable framework.", tag: "Implementing"),
                    ChecklistRequirement(title: "Safety Net Advice", guidance: "Tell the reader what safety rails to put in place first.", tag: "Implementing"),

                    // CTA
                    ChecklistRequirement(title: "Conversation Starter CTA", guidance: "Ask readers if they have experienced something similar.", tag: "CTA", template: "Have you ever found yourself in this position? How did you handle it?"),
                    ChecklistRequirement(title: "Share with Someone Struggling CTA", guidance: "Encourage forwarding to peers in similar situations.", tag: "CTA", template: "Share this with a founder who needs to hear this today."),
                    ChecklistRequirement(title: "Follow for More Stories CTA", guidance: "Invite follows for honest journey updates.", tag: "CTA", template: "Follow @handle for honest, transparent updates on the journey."),
                    ChecklistRequirement(title: "Bookmark for Hard Days CTA", guidance: "Prompt saving as inspiration during tough times.", tag: "CTA", template: "Bookmark this for the next time you feel stuck."),
                    ChecklistRequirement(title: "Drop Your Take Below CTA", guidance: "Ask what lesson they learned the hard way.", tag: "CTA", template: "What's the hardest lesson you've had to learn yourself?")
                ]
            ),

            // 5. Punchy Hot Take
            ContentStrategy(
                name: "Punchy Hot Take",
                emoji: "⚡",
                description: "Brevity at its finest. Under 140 characters, razor-sharp opinion.",
                items: [
                    // Hooks
                    ChecklistRequirement(title: "Under 100 Character Punch", guidance: "Fit the entire thesis in 1 tight sentence.", tag: "Hook", template: "[Concept A] is for amateurs. [Concept B] is for pros."),
                    ChecklistRequirement(title: "The Axiom / Maxim Hook", guidance: "State a timeless-sounding universal rule.", tag: "Hook", template: "The secret to [goal] isn't more effort. It's better selection."),
                    ChecklistRequirement(title: "The Direct Contradiction", guidance: "Contradict popular sentiment in 5 words.", tag: "Hook", template: "More features never save bad products."),
                    ChecklistRequirement(title: "The Uncomfortable Question Hook", guidance: "Ask a question that forces uncomfortable introspection.", tag: "Hook", template: "Are you actually building, or just playing founder?"),
                    ChecklistRequirement(title: "The Two-Word Contrast Hook", guidance: "Contrast two words with high impact.", tag: "Hook", template: "Discipline > Motivation. Always."),

                    // Writing
                    ChecklistRequirement(title: "No Fluff or Filler", guidance: "Cut every unnecessary adverb, caveat, or hedge.", tag: "Writing"),
                    ChecklistRequirement(title: "Punchy Cadence", guidance: "Read aloud to ensure it flows with sharp rhythm.", tag: "Writing"),
                    ChecklistRequirement(title: "Max Visual Contrast", guidance: "Use comparison formatting (X vs Y).", tag: "Writing"),
                    ChecklistRequirement(title: "Stand-Alone Quotability", guidance: "Make it fit as an easily screenshot-able quote.", tag: "Writing"),
                    ChecklistRequirement(title: "Zero Apologies Tone", guidance: "Own the perspective completely.", tag: "Writing"),

                    // Implementing
                    ChecklistRequirement(title: "Memorable One-Liner Rule", guidance: "State the rule so simply a 10-year-old would remember it.", tag: "Implementing"),
                    ChecklistRequirement(title: "Instant Diagnostic Question", guidance: "Give a 1-second mental test to assess oneself.", tag: "Implementing"),
                    ChecklistRequirement(title: "The 80/20 Rule Application", guidance: "Clarify what the critical 20% actually is.", tag: "Implementing"),
                    ChecklistRequirement(title: "Tweet Screenshot Ready", guidance: "Format so it looks gorgeous as an image.", tag: "Implementing"),
                    ChecklistRequirement(title: "Actionable Contrast", guidance: "Replace bad habit with good habit in 1 line.", tag: "Implementing"),

                    // CTA
                    ChecklistRequirement(title: "Agree or Disagree? CTA", guidance: "Prompt 1-word replies.", tag: "CTA", template: "Agree or disagree?"),
                    ChecklistRequirement(title: "Quote Tweet Trigger", guidance: "Prompt RT with their take.", tag: "CTA", template: "Quote-tweet if this hit home."),
                    ChecklistRequirement(title: "Thoughts? CTA", guidance: "Simple 1-word invitation to reply.", tag: "CTA", template: "Thoughts?"),
                    ChecklistRequirement(title: "Repost CTA", guidance: "Ask for repost if they agree.", tag: "CTA", template: "Repost to spread the truth."),
                    ChecklistRequirement(title: "Follow for Daily Hot Takes", guidance: "Quick follow callout.", tag: "CTA", template: "Follow @handle for daily insights.")
                ]
            )
        ]
    }
}
