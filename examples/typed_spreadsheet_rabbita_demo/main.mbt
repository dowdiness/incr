///|
fn main {
  @rabbita.new(app()).mount("app")
}

///|
fn app() -> @rabbita.Cell {
  @rabbita.cell(model=init_model(), update=update_with_cmd, view~)
}

///|
fn update_with_cmd(
  _emit : @rabbita.Emit[Msg],
  msg : Msg,
  model : Model,
) -> (@rabbita.Cmd, Model) {
  let next = update(msg, model)
  let cmd = match msg {
    BeginInlineEdit(cell) => focus_inline_editor_cmd(cell)
    _ => @rabbita.none
  }
  (cmd, next)
}

///|
fn focus_inline_editor_cmd(cell : String) -> @rabbita.Cmd {
  @rabbita_cmd.custom_cmd(
    fn(_) { js_focus_element_by_id(inline_editor_id(cell)) },
    kind=@rabbita_cmd.after_render,
  )
}

///|
extern "js" fn js_focus_element_by_id(id : String) -> Unit =
  #| function(id) {
  #|   var el = document.getElementById(id);
  #|   if (!el || typeof el.focus !== 'function') return;
  #|   try {
  #|     el.focus({ preventScroll: true });
  #|   } catch (_) {
  #|     el.focus();
  #|   }
  #|   if (typeof el.select === 'function') el.select();
  #| }
