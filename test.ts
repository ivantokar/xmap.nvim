// Test TypeScript file for xmap.nvim
// This file contains various TypeScript structures to test the minimap provider
// (This header block should be suppressed in the minimap)

export interface User {
  id: number
  name: string
  email?: string
}

export type Result<T> =
  | { ok: true; value: T }
  | { ok: false; error: Error }

export enum Status {
  Idle = "idle",
  Loading = "loading",
  Done = "done",
}

export function processUsers(users: User[]): number {
  return users.length
}

export const makeUser = (id: number, name: string): User => ({
  id,
  name,
})

const version = "1.0.0"

class UserManager {
  private users: User[] = []

  constructor() {}

  get userCount(): number {
    return this.users.length
  }

  set userCount(value: number) {
    this.users.length = value
  }

  addUser(user: User): void {
    this.users.push(user)
  }

  handleClick = (id: number) => {
    console.log("clicked", id)
  }

  // MARK: - Users
  // TODO: Add persistence
  // FIXME: Handle duplicates
}

namespace Utils {
  export function clamp(value: number, min: number, max: number): number {
    return Math.max(min, Math.min(max, value))
  }
}

