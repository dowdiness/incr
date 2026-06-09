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
#cfg(target="js")
extern "js" fn dom_request_animation_frame(callback : () -> Unit) -> Unit =
  #| (callback) => { window.requestAnimationFrame(() => callback()); }

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
) -> Unit {
  // Additive listener (#210): mounting the renderer must not clobber any
  // derived-event listener a host integration already installed. The returned
  // ListenerId is unused for now; #209 (unmount) will store it for removal.
  let _ = try! runtime.add_derived_event_listener(event => {
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
}

///|
#cfg(target="js")
fn[Msg] Rendered::node(self : Rendered[Msg]) -> DomNode {
  match self {
    RenderedText(_, node) => node
    RenderedElem(element~, ..) => dom_element_node(element)
  }
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
  dispatch : (Msg) -> Unit,
) -> Unit {
  for event in events {
    dom_add_event_listener(element, event.name, event.prevent_default, () => {
      dispatch(event.message)
    })
  }
}

///|
#cfg(target="js")
fn[Msg] render_html(
  html : Html[Msg],
  dispatch : (Msg) -> Unit,
) -> Rendered[Msg] {
  match html {
    Text(value) => RenderedText(value, dom_create_text(value))
    Elem(tag~, attrs~, events~, children~) => {
      let element = dom_create_element(tag)
      patch_attrs([], attrs, element)
      attach_events(element, events, dispatch)
      let rendered_children = children.map(child => {
        let rendered = render_html(child, dispatch)
        dom_append_child(element, rendered.node())
        rendered
      })
      RenderedElem(tag~, attrs~, events~, children=rendered_children, element~)
    }
  }
}

///|
#cfg(target="js")
fn[Msg : Eq] diff_rendered(
  old : Rendered[Msg],
  next : Html[Msg],
  parent : DomElement,
  dispatch : (Msg) -> Unit,
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
        replace_rendered(old, next, parent, dispatch)
      } else {
        patch_attrs(old_attrs, next_attrs, element)
        let rendered_children = diff_children(
          old_children, next_children, element, dispatch,
        )
        RenderedElem(
          tag=next_tag,
          attrs=next_attrs,
          events=next_events,
          children=rendered_children,
          element~,
        )
      }
    _ => replace_rendered(old, next, parent, dispatch)
  }
}

///|
#cfg(target="js")
fn[Msg] replace_rendered(
  old : Rendered[Msg],
  next : Html[Msg],
  parent : DomElement,
  dispatch : (Msg) -> Unit,
) -> Rendered[Msg] {
  let rendered = render_html(next, dispatch)
  dom_replace_child(parent, rendered.node(), old.node())
  rendered
}

///|
#cfg(target="js")
fn[Msg : Eq] diff_children(
  old_children : Array[Rendered[Msg]],
  next_children : Array[Html[Msg]],
  parent : DomElement,
  dispatch : (Msg) -> Unit,
) -> Array[Rendered[Msg]] {
  let old_len = old_children.length()
  let next_len = next_children.length()
  let common = if old_len < next_len { old_len } else { next_len }
  let rendered = []
  for i in 0..<common {
    rendered.push(
      diff_rendered(old_children[i], next_children[i], parent, dispatch),
    )
  }
  if next_len > old_len {
    for i in old_len..<next_len {
      let child = render_html(next_children[i], dispatch)
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
#cfg(target="js")
priv struct BrowserRoot[Msg] {
  watched : WatchedHtmlRoot[Msg]
  host : DomElement
  mut rendered : Rendered[Msg]?
}

///|
#cfg(target="js")
fn[Msg] BrowserRoot::BrowserRoot(
  program : Program[Msg, Html[Msg]],
  host : DomElement,
  stats : RenderStats,
) -> BrowserRoot[Msg] {
  {
    watched: WatchedHtmlRoot::WatchedHtmlRoot(program, stats),
    host,
    rendered: None,
  }
}

///|
#cfg(target="js")
fn[Msg : Eq] BrowserRoot::flush(self : BrowserRoot[Msg]) -> Unit {
  match self.watched.read_changed() {
    None => ()
    Some(next) => {
      let dispatch = msg => ignore(self.watched.program.dispatch(msg))
      match self.rendered {
        None => {
          let rendered = render_html(next, dispatch)
          dom_replace_children(self.host, rendered.node())
          self.rendered = Some(rendered)
        }
        Some(old) =>
          self.rendered = Some(diff_rendered(old, next, self.host, dispatch))
      }
    }
  }
}

///|
#cfg(target="js")
priv struct BrowserRenderer[Msg] {
  runtime : @incr.Runtime
  roots : Array[BrowserRoot[Msg]]
  stats : RenderStats
  view_ids : Ref[Array[@incr.CellId]]
  mut frame_scheduled : Bool
  after_flush : (RenderStats) -> Unit
}

///|
#cfg(target="js")
fn[Msg : Eq] BrowserRenderer::BrowserRenderer(
  runtime : @incr.Runtime,
  after_flush? : (RenderStats) -> Unit = _ => (),
) -> BrowserRenderer[Msg] {
  let stats = RenderStats::RenderStats()
  let view_ids : Ref[Array[@incr.CellId]] = Ref([])
  install_render_recompute_counter(runtime, view_ids, stats)
  let renderer = {
    runtime,
    roots: [],
    stats,
    view_ids,
    frame_scheduled: false,
    after_flush,
  }
  // Additive listener (#210): coexist with any pre-existing on-change hook.
  let _ = runtime.add_on_change_listener(() => renderer.schedule_flush())
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
) -> Unit {
  guard program.runtime().id() == self.runtime.id() else {
    abort("BrowserRenderer::mount called with a Program from another Runtime")
  }
  self.view_ids.val.push(program.view_id())
  let root = BrowserRoot::BrowserRoot(program, host, self.stats)
  self.roots.push(root)
  root.flush()
  (self.after_flush)(self.stats)
}

///|
#cfg(target="js")
fn[Msg : Eq] BrowserRenderer::schedule_flush(
  self : BrowserRenderer[Msg],
) -> Unit {
  if !self.frame_scheduled {
    self.frame_scheduled = true
    dom_request_animation_frame(() => {
      self.frame_scheduled = false
      self.stats.frame_flushes = self.stats.frame_flushes + 1
      for root in self.roots {
        root.flush()
      }
      (self.after_flush)(self.stats)
    })
  }
}
