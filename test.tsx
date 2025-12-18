// Test TSX file for xmap.nvim
// This file contains various TSX/React structures to test the minimap provider
// (This header block should be suppressed in the minimap)

import React from "react"

type Props = {
  title: string
  count?: number
}

function useTitle(title: string) {
  React.useEffect(() => {
    document.title = title
  }, [title])
}

export function Header({ title, count }: Props) {
  return (
    <header>
      <h1>{title}</h1>
      <span>{count ?? 0}</span>
    </header>
  )
}

export const MemoHeader = React.memo((p: Props) => {
  return <Header title={p.title} count={p.count} />
})

export const App: React.FC<Props> = (props) => {
  useTitle(props.title)

  const [count, setCount] = React.useState(props.count ?? 0)
  const doubled = React.useMemo(() => count * 2, [count])
  const increment = React.useCallback(() => setCount((c) => c + 1), [])

  return (
    <main>
      <button onClick={increment}>Increment</button>
      <Header title={props.title} count={doubled} />
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
