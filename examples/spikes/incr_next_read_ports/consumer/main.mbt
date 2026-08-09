///|
fn main {
  let passed = all_workloads()
  println(if passed { "read_ports workloads=true" } else { "read_ports workloads=false" })
  if !passed {
    abort("read-port workload failed")
  }
}
