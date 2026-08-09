///|
fn main {
  let passed = all_workloads()
  println(
    if passed {
      "cross_program_ports workloads=true"
    } else {
      "cross_program_ports workloads=false"
    },
  )
  if !passed {
    abort("cross-program port workload failed")
  }
}
