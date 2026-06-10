///|
#cfg(target="js")
#external
priv type DomNode

///|
#cfg(target="js")
#external
priv type DomElement

///|
#cfg(target="js")
extern "js" fn dom_get_element_by_id(id : String) -> DomElement =
  #| (id) => {
  #|   const el = document.getElementById(id);
  #|   if (!el) throw new Error(`missing DOM mount #${id}`);
  #|   return el;
  #| }

///|
#cfg(target="js")
extern "js" fn dom_query_child_by_id(
  parent : DomElement,
  id : String,
) -> DomElement =
  #| (parent, id) => {
  #|   const el = parent.querySelector("#" + id);
  #|   if (!el) throw new Error(`missing DOM mount #${id}`);
  #|   return el;
  #| }

///|
#cfg(target="js")
extern "js" fn dom_create_element(tag : String) -> DomElement =
  #| (tag) => document.createElement(tag)

///|
#cfg(target="js")
extern "js" fn dom_create_text(value : String) -> DomNode =
  #| (value) => document.createTextNode(value)

///|
#cfg(target="js")
extern "js" fn dom_element_node(element : DomElement) -> DomNode =
  #| (element) => element

///|
#cfg(target="js")
extern "js" fn dom_append_child(parent : DomElement, child : DomNode) -> Unit =
  #| (parent, child) => { parent.appendChild(child); }

///|
#cfg(target="js")
extern "js" fn dom_replace_children(
  parent : DomElement,
  child : DomNode,
) -> Unit =
  #| (parent, child) => { parent.replaceChildren(child); }

///|
#cfg(target="js")
extern "js" fn dom_replace_child(
  parent : DomElement,
  next : DomNode,
  old : DomNode,
) -> Unit =
  #| (parent, next, old) => { parent.replaceChild(next, old); }

///|
#cfg(target="js")
extern "js" fn dom_remove_child(parent : DomElement, child : DomNode) -> Unit =
  #| (parent, child) => { parent.removeChild(child); }

///|
#cfg(target="js")
extern "js" fn dom_set_text(node : DomNode, value : String) -> Unit =
  #| (node, value) => { node.nodeValue = value; }

///|
#cfg(target="js")
extern "js" fn dom_set_attr(
  element : DomElement,
  name : String,
  value : String,
) -> Unit =
  #| (element, name, value) => { element.setAttribute(name, value); }

///|
#cfg(target="js")
extern "js" fn dom_remove_attr(element : DomElement, name : String) -> Unit =
  #| (element, name) => { element.removeAttribute(name); }

///|
#cfg(target="js")
extern "js" fn dom_add_event_listener(
  element : DomElement,
  name : String,
  prevent_default : Bool,
  callback : () -> Unit,
) -> Unit =
  #| (element, name, preventDefault, callback) => {
  #|   element.addEventListener(name, event => {
  #|     if (preventDefault) event.preventDefault();
  #|     callback();
  #|   });
  #| }

///|
/// DOM-payload listener for text inputs: forwards the target's string `value`.
/// The value→message mapping stays at the browser boundary; `Html` only stores
/// the pure tag (see `EventSpec::Input`).
#cfg(target="js")
extern "js" fn dom_add_value_listener(
  element : DomElement,
  name : String,
  prevent_default : Bool,
  callback : (String) -> Unit,
) -> Unit =
  #| (element, name, preventDefault, callback) => {
  #|   element.addEventListener(name, event => {
  #|     if (preventDefault) event.preventDefault();
  #|     const target = event.target;
  #|     callback(target && target.value != null ? String(target.value) : "");
  #|   });
  #| }

///|
#cfg(target="js")
extern "js" fn dom_request_animation_frame(callback : () -> Unit) -> Bool =
  #| (callback) => {
  #|   if (typeof window !== "undefined" && window.requestAnimationFrame) {
  #|     window.requestAnimationFrame(() => callback());
  #|     return true;
  #|   }
  #|   // No animation-frame clock (e.g. Node test runs): drop the frame and
  #|   // report that nothing was queued, so the caller does not latch a pending
  #|   // frame that will never fire.
  #|   return false;
  #| }

///|
#cfg(target="js")
extern "js" fn dom_set_element_text(
  element : DomElement,
  value : String,
) -> Unit =
  #| (element, value) => { element.textContent = value; }

///|
#cfg(target="js")
fn[Msg, View] Program::view_id(self : Program[Msg, View]) -> @incr.CellId {
  self._view_id
}

///|
#cfg(target="js")
fn view_id_is_tracked(ids : Array[@incr.CellId], id : @incr.CellId) -> Bool {
  for tracked in ids {
    if tracked == id {
      return true
    }
  }
  false
}

///|
#cfg(target="js")
fn install_render_recompute_counter(
  runtime : @incr.Runtime,
  view_ids : Ref[Array[@incr.CellId]],
  stats : RenderStats,
) -> @incr.ListenerId {
  // Additive listener (#210): mounting the renderer must not clobber any
  // derived-event listener a host integration already installed. The returned
  // ListenerId is stored on the renderer so dispose (#209) can remove it.
  try! runtime.add_derived_event_listener(event => {
    match event {
      @incr.DerivedEvent::Completed(completed) =>
        if view_id_is_tracked(view_ids.val, completed.cell_id) {
          stats.view_recomputes = stats.view_recomputes + 1
        }
      _ => ()
    }
  })
}

///|
#cfg(target="js")
priv enum Rendered[Msg] {
  RenderedText(String, DomNode)
  RenderedElem(
    tag~ : String,
    attrs~ : Array[Attribute],
    events~ : Array[EventBinding[Msg]],
    children~ : Array[Rendered[Msg]],
    element~ : DomElement
  )
  RenderedKeyedElem(
    tag~ : String,
    attrs~ : Array[Attribute],
    events~ : Array[EventBinding[Msg]],
    children~ : Array[(String, Rendered[Msg])],
    element~ : DomElement
  )
}

///|
#cfg(target="js")
fn[Msg] Rendered::node(self : Rendered[Msg]) -> DomNode {
  match self {
    RenderedText(_, node) => node
    RenderedElem(element~, ..) => dom_element_node(element)
    RenderedKeyedElem(element~, ..) => dom_element_node(element)
  }
}

///|
/// Boundary handles the renderer threads through render/diff so DOM listeners
/// can re-enter the program. `dispatch` forwards a fixed message; `resolve_text`
/// maps a text input's `(tag, value)` to a message (or `None` to ignore it).
/// Both are created once per flush at the browser boundary, never stored in the
/// cacheable `Html` value.
#cfg(target="js")
priv struct EventSink[Msg] {
  dispatch : (Msg) -> Unit
  resolve_text : (String, String) -> Msg?
}

///|
#cfg(target="js")
fn attr_value(attrs : Array[Attribute], name : String) -> String? {
  for attr in attrs {
    if attr.name == name {
      return Some(attr.value)
    }
  }
  None
}

///|
#cfg(target="js")
fn patch_attrs(
  old_attrs : Array[Attribute],
  new_attrs : Array[Attribute],
  element : DomElement,
) -> Unit {
  for old in old_attrs {
    if attr_value(new_attrs, old.name) is None {
      dom_remove_attr(element, old.name)
    }
  }
  for next in new_attrs {
    match attr_value(old_attrs, next.name) {
      None => dom_set_attr(element, next.name, next.value)
      Some(prev) =>
        if prev != next.value {
          dom_set_attr(element, next.name, next.value)
        }
    }
  }
}

///|
#cfg(target="js")
fn[Msg] attach_events(
  element : DomElement,
  events : Array[EventBinding[Msg]],
  sink : EventSink[Msg],
) -> Unit {
  let dispatch = sink.dispatch
  let resolve_text = sink.resolve_text
  for event in events {
    match event.spec {
      Const(message) =>
        dom_add_event_listener(element, event.name, event.prevent_default, () => {
          dispatch(message)
        })
      Input(tag~) =>
        dom_add_value_listener(element, event.name, event.prevent_default, value => {
          match resolve_text(tag, value) {
            Some(message) => dispatch(message)
            None => ()
          }
        })
    }
  }
}

///|
#cfg(target="js")
fn[Msg] render_html(html : Html[Msg], sink : EventSink[Msg]) -> Rendered[Msg] {
  match html {
    Text(value) => RenderedText(value, dom_create_text(value))
    Elem(tag~, attrs~, events~, children~) => {
      let element = dom_create_element(tag)
      patch_attrs([], attrs, element)
      attach_events(element, events, sink)
      let rendered_children = children.map(child => {
        let rendered = render_html(child, sink)
        dom_append_child(element, rendered.node())
        rendered
      })
      RenderedElem(tag~, attrs~, events~, children=rendered_children, element~)
    }
    KeyedElem(tag~, attrs~, events~, children~) => {
      let element = dom_create_element(tag)
      patch_attrs([], attrs, element)
      attach_events(element, events, sink)
      let rendered_children = children.map(pair => {
        let (key, child) = pair
        let rendered = render_html(child, sink)
        dom_append_child(element, rendered.node())
        (key, rendered)
      })
      RenderedKeyedElem(
        tag~,
        attrs~,
        events~,
        children=rendered_children,
        element~,
      )
    }
  }
}

///|
#cfg(target="js")
fn[Msg : Eq] diff_rendered(
  old : Rendered[Msg],
  next : Html[Msg],
  parent : DomElement,
  sink : EventSink[Msg],
) -> Rendered[Msg] {
  match (old, next) {
    (RenderedText(old_text, node), Text(next_text)) => {
      if old_text != next_text {
        dom_set_text(node, next_text)
      }
      RenderedText(next_text, node)
    }
    (
      RenderedElem(
        tag=old_tag,
        attrs=old_attrs,
        events=old_events,
        children=old_children,
        element~
      ),
      Elem(
        tag=next_tag,
        attrs=next_attrs,
        events=next_events,
        children=next_children
      ),
    ) =>
      if old_tag != next_tag || old_events != next_events {
        replace_rendered(old, next, parent, sink)
      } else {
        patch_attrs(old_attrs, next_attrs, element)
        let rendered_children = diff_children(
          old_children, next_children, element, sink,
        )
        RenderedElem(
          tag=next_tag,
          attrs=next_attrs,
          events=next_events,
          children=rendered_children,
          element~,
        )
      }
    (
      RenderedKeyedElem(
        tag=old_tag,
        attrs=old_attrs,
        events=old_events,
        children=old_children,
        element~
      ),
      KeyedElem(
        tag=next_tag,
        attrs=next_attrs,
        events=next_events,
        children=next_children
      ),
    ) =>
      if old_tag != next_tag || old_events != next_events {
        replace_rendered(old, next, parent, sink)
      } else {
        patch_attrs(old_attrs, next_attrs, element)
        let rendered_children = diff_keyed_children(
          old_children, next_children, element, sink,
        )
        RenderedKeyedElem(
          tag=next_tag,
          attrs=next_attrs,
          events=next_events,
          children=rendered_children,
          element~,
        )
      }
    // Mode switch (positional <-> keyed) or tag/kind change: rebuild the node.
    _ => replace_rendered(old, next, parent, sink)
  }
}

///|
#cfg(target="js")
fn[Msg] replace_rendered(
  old : Rendered[Msg],
  next : Html[Msg],
  parent : DomElement,
  sink : EventSink[Msg],
) -> Rendered[Msg] {
  let rendered = render_html(next, sink)
  dom_replace_child(parent, rendered.node(), old.node())
  rendered
}

///|
#cfg(target="js")
fn[Msg : Eq] diff_children(
  old_children : Array[Rendered[Msg]],
  next_children : Array[Html[Msg]],
  parent : DomElement,
  sink : EventSink[Msg],
) -> Array[Rendered[Msg]] {
  let old_len = old_children.length()
  let next_len = next_children.length()
  let common = if old_len < next_len { old_len } else { next_len }
  let rendered = []
  for i in 0..<common {
    rendered.push(
      diff_rendered(old_children[i], next_children[i], parent, sink),
    )
  }
  if next_len > old_len {
    for i in old_len..<next_len {
      let child = render_html(next_children[i], sink)
      dom_append_child(parent, child.node())
      rendered.push(child)
    }
  } else if old_len > next_len {
    for i in old_len>..next_len {
      dom_remove_child(parent, old_children[i].node())
    }
  }
  rendered
}

///|
/// Keyed child reconciliation (#211). The pure `plan_keyed_diff` decides which
/// new child reuses which old node (by key) and which old nodes are removed;
/// this applier performs the DOM mutations.
///
/// Survivors and freshly created nodes are appended in new order: `appendChild`
/// on an already-attached node moves it to the end, so replaying the new order
/// left-to-right leaves the parent's children in exactly the new order while
/// reusing each key's DOM node (and its listeners). Removals run first so a
/// vanished node is detached before survivors are re-appended.
///
/// Tradeoff: every keyed child is re-appended when anything changes, so this is
/// not minimal-move (a focused/selected reused node can be reparented). It only
/// runs when the view value already changed (value-level `Eq` skips unchanged
/// views), and identity is preserved per key. An anchor-based minimal-move pass
/// (LIS / two-ended) is a follow-up if a benchmark or focus-retention need
/// justifies it.
#cfg(target="js")
fn[Msg : Eq] diff_keyed_children(
  old_children : Array[(String, Rendered[Msg])],
  next_children : Array[(String, Html[Msg])],
  parent : DomElement,
  sink : EventSink[Msg],
) -> Array[(String, Rendered[Msg])] {
  let old_keys = old_children.map(pair => pair.0)
  let new_keys = next_children.map(pair => pair.0)
  let plan = plan_keyed_diff(old_keys, new_keys)
  plan.removals.each(index => {
    dom_remove_child(parent, old_children[index].1.node())
  })
  // Reconcile in new order: reuse the matched old node or render a fresh one,
  // then append (appendChild moves an attached node, so replaying the new order
  // leaves the parent's children in exactly the new order).
  plan.steps.mapi((idx, step) => {
    let (key, html) = next_children[idx]
    let child = match step {
      Some(old_index) =>
        diff_rendered(old_children[old_index].1, html, parent, sink)
      None => render_html(html, sink)
    }
    dom_append_child(parent, child.node())
    (key, child)
  })
}

///|
#cfg(target="js")
priv struct BrowserRoot[Msg] {
  watched : WatchedHtmlRoot[Msg]
  host : DomElement
  // Mount-time boundary resolver for text-input payloads: `(tag, value) -> Msg?`.
  // Stays at the browser boundary (never in the cacheable `Html` value); roots
  // without text inputs use the default that ignores every payload.
  resolve_text : (String, String) -> Msg?
  mut rendered : Rendered[Msg]?
}

///|
#cfg(target="js")
fn[Msg] BrowserRoot::BrowserRoot(
  program : Program[Msg, Html[Msg]],
  host : DomElement,
  stats : RenderStats,
  resolve_text? : (String, String) -> Msg? = (_, _) => None,
) -> BrowserRoot[Msg] {
  {
    watched: WatchedHtmlRoot::WatchedHtmlRoot(program, stats),
    host,
    resolve_text,
    rendered: None,
  }
}

///|
#cfg(target="js")
fn[Msg : Eq] BrowserRoot::flush(self : BrowserRoot[Msg]) -> Unit {
  match self.watched.read_changed() {
    None => ()
    Some(next) => {
      let sink : EventSink[Msg] = {
        dispatch: msg => ignore(self.watched.program.dispatch(msg)),
        resolve_text: self.resolve_text,
      }
      match self.rendered {
        None => {
          let rendered = render_html(next, sink)
          dom_replace_children(self.host, rendered.node())
          self.rendered = Some(rendered)
        }
        Some(old) =>
          self.rendered = Some(diff_rendered(old, next, self.host, sink))
      }
    }
  }
}

///|
/// The component cell id this root tracks — the key used to drop the root from
/// the renderer's flush set and instrumentation filter.
#cfg(target="js")
fn[Msg] BrowserRoot::view_id(self : BrowserRoot[Msg]) -> @incr.CellId {
  self.watched.program.view_id()
}

///|
/// Removes the root's rendered subtree from its host without disposing the
/// logical component. The program scope and watch stay alive, so the renderer can
/// re-attach the same root later (`BrowserRenderer::reattach`). Both DOM caches
/// are reset — `rendered` and the watched `last_view` — because the subtree is
/// gone, so a later re-attach renders from scratch instead of being skipped as
/// "unchanged".
#cfg(target="js")
fn[Msg] BrowserRoot::detach(self : BrowserRoot[Msg]) -> Unit {
  match self.rendered {
    Some(rendered) => {
      dom_remove_child(self.host, rendered.node())
      self.rendered = None
    }
    None => ()
  }
  self.watched.last_view = None
}

///|
/// Disposes the root's program scope (releasing the view watch and owned cells).
/// Idempotent. Kept separate from DOM teardown because the same `Program` can
/// back more than one mounted root, so the caller decides when the last root is
/// gone. See `BrowserRenderer::destroy`.
#cfg(target="js")
fn[Msg] BrowserRoot::dispose_program(self : BrowserRoot[Msg]) -> Unit {
  self.watched.program.dispose()
}

///|
/// Tears the root down logically: detaches its DOM, then disposes the program
/// scope. Used by the whole-renderer `dispose`, where every root is going away,
/// so disposing each program (idempotent for a shared one) is correct.
#cfg(target="js")
fn[Msg] BrowserRoot::destroy(self : BrowserRoot[Msg]) -> Unit {
  self.detach()
  self.dispose_program()
}

///|
#cfg(target="js")
priv struct BrowserRenderer[Msg] {
  runtime : @incr.Runtime
  // Mounted roots, flushed on every animation frame.
  mut roots : Array[BrowserRoot[Msg]]
  // Detached-but-alive roots (#209): removed from the DOM but their Program is
  // kept so they can be re-attached. The renderer still owns them, so `dispose`
  // tears them down too instead of leaking them.
  mut detached : Array[BrowserRoot[Msg]]
  stats : RenderStats
  view_ids : Ref[Array[@incr.CellId]]
  mut frame_scheduled : Bool
  after_flush : (RenderStats) -> Unit
  // Lifecycle (#209). The two listener ids are removed on dispose so a torn-down
  // renderer stops reacting to runtime changes and view recomputes. The
  // on_change id is set after construction because its listener closure captures
  // `renderer` itself; it is `None` only during that construction window.
  mut disposed : Bool
  derived_listener_id : @incr.ListenerId
  mut on_change_listener_id : @incr.ListenerId?
}

///|
#cfg(target="js")
fn[Msg : Eq] BrowserRenderer::BrowserRenderer(
  runtime : @incr.Runtime,
  after_flush? : (RenderStats) -> Unit = _ => (),
) -> BrowserRenderer[Msg] {
  let stats = RenderStats::RenderStats()
  let view_ids : Ref[Array[@incr.CellId]] = Ref([])
  let derived_listener_id = install_render_recompute_counter(
    runtime, view_ids, stats,
  )
  let renderer = {
    runtime,
    roots: [],
    detached: [],
    stats,
    view_ids,
    frame_scheduled: false,
    after_flush,
    disposed: false,
    derived_listener_id,
    on_change_listener_id: None,
  }
  // Additive listener (#210): coexist with any pre-existing on-change hook. Its
  // closure captures `renderer`, so the id is recorded after construction.
  renderer.on_change_listener_id = Some(
    runtime.add_on_change_listener(() => renderer.schedule_flush()),
  )
  renderer
}

///|
#cfg(target="js")
fn[Msg] BrowserRenderer::stats(self : BrowserRenderer[Msg]) -> RenderStats {
  self.stats
}

///|
#cfg(target="js")
fn[Msg : Eq] BrowserRenderer::mount(
  self : BrowserRenderer[Msg],
  host : DomElement,
  program : Program[Msg, Html[Msg]],
  on_input? : (String, String) -> Msg? = (_, _) => None,
) -> BrowserRoot[Msg] {
  guard !self.disposed else {
    abort("BrowserRenderer::mount called after dispose")
  }
  guard program.runtime().id() == self.runtime.id() else {
    abort("BrowserRenderer::mount called with a Program from another Runtime")
  }
  let view_id = program.view_id()
  // One instrumentation id per Program, even if it backs several mounted roots.
  if !view_id_is_tracked(self.view_ids.val, view_id) {
    self.view_ids.val.push(view_id)
  }
  let root = BrowserRoot::BrowserRoot(
    program,
    host,
    self.stats,
    resolve_text=on_input,
  )
  self.roots.push(root)
  root.flush()
  (self.after_flush)(self.stats)
  root
}

///|
#cfg(target="js")
fn[Msg : Eq] BrowserRenderer::schedule_flush(
  self : BrowserRenderer[Msg],
) -> Unit {
  guard !self.disposed else { return }
  if !self.frame_scheduled {
    // Only latch when a real animation frame was queued. In a non-browser env
    // (no rAF clock) the frame is dropped, and latching would wedge the renderer
    // permanently "scheduled" so no later change ever flushes.
    let queued = dom_request_animation_frame(() => {
      self.frame_scheduled = false
      // A frame queued before dispose can still fire after it; iterating the
      // (now empty) root set would be harmless, but bail explicitly so a
      // disposed renderer never touches the DOM or runs after_flush.
      guard !self.disposed else { return }
      self.stats.frame_flushes = self.stats.frame_flushes + 1
      for root in self.roots {
        root.flush()
      }
      (self.after_flush)(self.stats)
    })
    if queued {
      self.frame_scheduled = true
    }
  }
}

///|
/// Removes exactly `root` (by physical identity) from both the mounted and the
/// detached buckets. Pure bookkeeping — no DOM or program access.
#cfg(target="js")
fn[Msg] BrowserRenderer::remove_root(
  self : BrowserRenderer[Msg],
  root : BrowserRoot[Msg],
) -> Unit {
  self.roots = self.roots.filter(other => !physical_equal(other, root))
  self.detached = self.detached.filter(other => !physical_equal(other, root))
}

///|
/// Whether any root the renderer still owns (mounted or detached) references the
/// `Program` identified by `view_id`. The single source of truth for "is this the
/// last root for this Program?", used to decide both program disposal and
/// instrumentation-id removal.
#cfg(target="js")
fn[Msg] BrowserRenderer::references_program(
  self : BrowserRenderer[Msg],
  view_id : @incr.CellId,
) -> Bool {
  self.roots.iter().any(other => other.view_id() == view_id) ||
  self.detached.iter().any(other => other.view_id() == view_id)
}

///|
/// Detaches a mounted root: removes its DOM subtree but keeps the Program alive,
/// and parks the root so a later rAF will not re-render it. The renderer still
/// owns it (so `dispose` reclaims it); re-attach with `reattach`. No-op if `root`
/// is not currently mounted.
#cfg(target="js")
fn[Msg] BrowserRenderer::detach(
  self : BrowserRenderer[Msg],
  root : BrowserRoot[Msg],
) -> Unit {
  guard self.roots.iter().any(other => physical_equal(other, root)) else {
    return
  }
  root.detach()
  self.roots = self.roots.filter(other => !physical_equal(other, root))
  self.detached.push(root)
}

///|
/// Re-attaches a parked root: moves it back to the mounted set and renders it
/// from scratch into its host (detach reset both DOM caches). No-op if the
/// renderer is disposed or `root` is not currently detached.
#cfg(target="js")
fn[Msg : Eq] BrowserRenderer::reattach(
  self : BrowserRenderer[Msg],
  root : BrowserRoot[Msg],
) -> Unit {
  guard !self.disposed else { return }
  guard self.detached.iter().any(other => physical_equal(other, root)) else {
    return
  }
  self.detached = self.detached.filter(other => !physical_equal(other, root))
  self.roots.push(root)
  root.flush()
}

///|
/// Destroys a single root — mounted or detached: tears down its DOM, removes it
/// from both buckets, and disposes the Program when no sibling root still
/// references it, so destroying one of several mounts of a shared component
/// leaves the others working. The instrumentation id is dropped on the same
/// last-reference condition.
#cfg(target="js")
fn[Msg] BrowserRenderer::destroy(
  self : BrowserRenderer[Msg],
  root : BrowserRoot[Msg],
) -> Unit {
  root.detach()
  self.remove_root(root)
  let view_id = root.view_id()
  if !self.references_program(view_id) {
    root.dispose_program()
    self.view_ids.val = self.view_ids.val.filter(id => id != view_id)
  }
}

///|
/// Tears the whole renderer down: removes its two runtime listeners, then
/// destroys every root it owns — mounted and detached. Idempotent.
///
/// `remove_derived_event_listener` is Idle-only and raises otherwise, so dispose
/// must be called outside a flush / propagation window; `try!` fails fast on
/// misuse (a raise here aborts — it is not recoverable, and swallowing it would
/// leave the view-recompute listener firing on a "disposed" renderer).
#cfg(target="js")
fn[Msg] BrowserRenderer::dispose(self : BrowserRenderer[Msg]) -> Unit {
  guard !self.disposed else { return }
  // Remove the Idle-only (raising) listener FIRST. `remove_derived_event_listener`
  // raises if called during a flush/propagation window, and `try!` turns that into
  // a fail-fast abort. Doing it before any other teardown keeps the abort atomic:
  // on misuse the renderer is still fully intact, never half-torn-down.
  try! self.runtime.remove_derived_event_listener(self.derived_listener_id)
  match self.on_change_listener_id {
    Some(id) => self.runtime.remove_on_change_listener(id)
    None => ()
  }
  self.disposed = true
  // Snapshot both buckets before teardown: destroy() must not race a mutation,
  // and detached (parked-but-alive) roots must be reclaimed, not leaked.
  let mounted = self.roots
  let parked = self.detached
  self.roots = []
  self.detached = []
  for root in mounted {
    root.destroy()
  }
  for root in parked {
    root.destroy()
  }
}
