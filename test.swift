// Test Swift file for xmap.nvim
// This file contains various Swift structures to test Tree-sitter integration

import Foundation

// A simple struct
struct User {
    let id: Int
    let name: String
    var email: String
}

// A class with properties and methods
class UserManager {
    private var users: [User] = []

    // Initializer
    init() {
        self.users = []
    }

    // Method to add user
    func addUser(_ user: User) {
        users.append(user)
        print("Added user: \(user.name)")
    }

    // Method to find user
    func findUser(byId id: Int) -> User? {
        return users.first { $0.id == id }
    }

    // Method to remove user
    func removeUser(byId id: Int) {
        users.removeAll { $0.id == id }
    }

    // Computed property
    var userCount: Int {
        return users.count
    }

    // Deinitializer
    deinit {
        print("UserManager deallocated")
    }
}

// Protocol definition
protocol Identifiable {
    var id: Int { get }
}

// Extension
extension User: Identifiable {}

// Enum with associated values
enum Result<T> {
    case success(T)
    case failure(Error)
}

// A function
func processUsers(_ users: [User]) -> Int {
    var count = 0

    for user in users {
        print("Processing: \(user.name)")
        count += 1
    }

    return count
}

// Generic function
func fetchData<T>(completion: @escaping (Result<T>) -> Void) {
    // Simulate async operation
    DispatchQueue.global().async {
        // Process data
        completion(.success("Data" as! T))
    }
}

// Another struct with methods
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
