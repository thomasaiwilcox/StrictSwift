// Demo file to show SourceKit semantic analysis difference
import Foundation

// MARK: - Case 1: Force unwrap - should be detected
class NetworkManager {
    static let shared = NetworkManager()
    var session: URLSession?
    
    func fetch() {
        // Force unwrap - MUST be detected
        let s = session!  // VIOLATION: force_unwrap
        let x: String? = "test"
        print(x!)  // VIOLATION: force_unwrap
        print(s)
    }
}

// MARK: - Case 1b: Force try - should be detected
func riskyOperation() throws -> String { return "ok" }
func caller() {
    let result = try! riskyOperation()  // VIOLATION: force_try
    print(result)
}

// MARK: - Case 2: Retain cycle detection with complex type relationships  
class ViewController {
    var onComplete: (() -> Void)?
    var name: String = "Test"
    
    func setup() {
        // This is a retain cycle - closure captures self strongly
        onComplete = {
            print(self.name)  // Captures self strongly
        }
    }
    
    func setupSafe() {
        // This is safe - uses weak self
        onComplete = { [weak self] in
            print(self?.name ?? "")
        }
    }
}

// MARK: - Case 3: Type inference ambiguity
protocol DataSource {
    func load()
}

class LocalDataSource: DataSource {
    func load() { print("local") }
}

class RemoteDataSource: DataSource {
    func load() { print("remote") }
}

class DataManager {
    // With SourceKit, we know the exact type here
    let source: DataSource = LocalDataSource()
    
    func refresh() {
        source.load()
    }
}

// MARK: - Case 4: Dead code with protocol conformance
protocol Serializable {
    func serialize() -> Data
}

class User: Serializable {
    let id: Int = 1
    
    // This is NOT dead - it's a protocol requirement
    func serialize() -> Data {
        return Data()
    }
    
    // This IS dead - never called
    private func unusedHelper() {
        print("never called")
    }
}

// Entry point to make some things "used"
func main() {
    let nm = NetworkManager.shared
    nm.fetch()
    
    let vc = ViewController()
    vc.setup()
    
    let dm = DataManager()
    dm.refresh()
    
    let user = User()
    _ = user.serialize()
}
