///|
async fn main {
  let mut state = initial_state()
  for ;; {
    println(render_frame(state))
    match @stdio.stdin.read_until("\n") {
      None => break
      Some(line) => {
        let command = line.trim()
        if command == "q" {
          break
        }
        state = apply_command(state, command)
      }
    }
  }
}
