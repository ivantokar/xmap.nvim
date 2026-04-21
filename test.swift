// AI HINTS: Test Swift file for xmap.nvim
// AI HINTS: This file contains various Swift structures to test Tree-sitter integration

import Foundation

// AI HINTS: A simple struct
struct User {
    let id: Int
    let name: String
    var email: String
}

// AI HINTS: A class with properties and methods
class UserManager {
    private var users: [User] = []

    // AI HINTS: Initializer
    init() {
        self.users = []
    }

    // AI HINTS: Method to add user
    func addUser(_ user: User) {
        users.append(user)
        print("Added user: \(user.name)")
    }

    // AI HINTS: Method to find user
    func findUser(byId id: Int) -> User? {
        return users.first { $0.id == id }
    }

    // AI HINTS: Method to remove user
    func removeUser(byId id: Int) {
        users.removeAll { $0.id == id }
    }

    // AI HINTS: Computed property
    var userCount: Int {
        return users.count
    }

    // AI HINTS: Deinitializer
    deinit {
        print("UserManager deallocated")
    }
}

// AI HINTS: Protocol definition
protocol Identifiable {
    var id: Int { get }
}

// AI HINTS: Extension
extension User: Identifiable {}

// AI HINTS: Enum with associated values
enum Result<T> {
    case success(T)
    case failure(Error)
}

// AI HINTS: A function
func processUsers(_ users: [User]) -> Int {
    var count = 0

    for user in users {
        print("Processing: \(user.name)")
        count += 1
    }

    return count
}

// AI HINTS: Generic function
func fetchData<T>(completion: @escaping (Result<T>) -> Void) {
    // AI HINTS: Simulate async operation
    DispatchQueue.global().async {
        // AI HINTS: Process data
        completion(.success("Data" as! T))
    }
}

// AI HINTS: Another struct with methods
struct Configuration {
    var width: Int
    var height: Int

    mutating func resize(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    func area() -> Int {
        return width * height
    }
}
