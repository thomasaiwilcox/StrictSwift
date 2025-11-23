import Foundation

actor Cache {
    private var storage: [String: Data] = [:]

    func get(_ key: String) -> Data? {
        return storage[key]
    }

    func set(_ key: String, _ value: Data) {
        storage[key] = value
    }
}

// VIOLATION: Non-Sendable Cache captured inside @Sendable closure
func processItems(items: [String]) async {
    let cache = Cache()

    await withTaskGroup(of: Void.self) { group in
        for item in items {
            group.addTask { @Sendable in
                // This should trigger a violation - Cache is not Sendable
                let data = await cache.get(item)
                processData(data)
            }
        }
    }
}

// VIOLATION: Mutable global state accessed from async context
var globalCounter = 0

func incrementGlobally() async {
    await MainActor.run {
        globalCounter += 1  // This might be OK, but flagged for review
    }
}

// SAFE EXAMPLE: Sendable value captured
func safeProcessing(items: [String]) async {
    let config = "config-string"  // String is Sendable

    await withTaskGroup(of: Void.self) { group in
        for item in items {
            group.addTask { @Sendable in
                // This is safe - config is Sendable
                process(item, with: config)
            }
        }
    }
}

private func processData(_ data: Data?) {}
private func process(_ item: String, with config: String) {}