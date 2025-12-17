// Test TSX file for xmap.nvim
// This file contains various TSX/React structures to test the minimap provider
// (This header block should be suppressed in the minimap)

import React from "react"

type Props = {
  title: string
  count?: number
}

export function Header({ title, count }: Props) {
  return (
    <header>
      <h1>{title}</h1>
      <span>{count ?? 0}</span>
    </header>
  )
}

export const App: React.FC<Props> = (props) => {
  return (
    <main>
      <Header title={props.title} count={props.count} />
    </main>
  )
}

class Store {
  private value: number = 0

  get current(): number {
    return this.value
  }

  set current(next: number) {
    this.value = next
  }

  increment(): void {
    this.value += 1
  }

  onChange = (next: number) => {
    this.value = next
  }
}

