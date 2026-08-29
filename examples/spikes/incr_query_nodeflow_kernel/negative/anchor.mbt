///|
#warnings("-unused_value")
fn identities_remain_usable_as_opaque_keys(
  node : @nodeflow.NodeReference,
  port : @nodeflow.PortReference,
  parameter : @nodeflow.ParameterReference,
  action : @nodeflow.ActionReference,
) -> Bool {
  ignore(port)
  ignore(parameter)
  ignore(action)
  node == node
}
