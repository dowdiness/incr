///|
#cfg(target="js")
#external
priv type DomNode

///|
#cfg(target="js")
#external
pub type DomElement

///|
#cfg(target="js")
pub extern "js" fn dom_get_element_by_id(id : String) -> DomElement =
  #| (id) => {
  #|   const el = document.getElementById(id);
  #|   if (!el) throw new Error(`missing DOM mount #${id}`);
  #|   return el;
  #| }

///|
#cfg(target="js")
pub extern "js" fn dom_query_child_by_id(
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
extern "js" fn dom_focus_element_by_id(id : String, select_text : Bool) -> Unit =
  #| (id, selectText) => {
  #|   const el = document.getElementById(id);
  #|   if (!el || typeof el.focus !== "function") return;
  #|   try {
  #|     el.focus({ preventScroll: true });
  #|   } catch (_) {
  #|     el.focus();
  #|   }
  #|   if (selectText && typeof el.select === "function") el.select();
  #| }

///|
/// Focuses a DOM element by id after the next renderer flush.
///
/// The effect is queued through `Cmd::after_flush`, so it can target elements
/// that were created by the DOM patch for the message that returned this
/// command. Set `select=true` for inline text editors.
#cfg(target="js")
pub fn[Msg] Cmd::focus_element_by_id(
  id : String,
  select? : Bool = false,
) -> Cmd[Msg] {
  Cmd::after_flush(_ => dom_focus_element_by_id(id, select))
}

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
extern "js" fn dom_set_value_property(
  element : DomElement,
  value : String,
) -> Unit =
  #| (element, value) => { element.value = value; }

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
  stop_propagation : Bool,
  callback : () -> Unit,
) -> Unit =
  #| (element, name, preventDefault, stopPropagation, callback) => {
  #|   element.addEventListener(name, event => {
  #|     if (preventDefault && typeof event.preventDefault === "function") event.preventDefault();
  #|     if (stopPropagation && typeof event.stopPropagation === "function") event.stopPropagation();
  #|     callback();
  #|   });
  #| }

///|
/// DOM-payload listener for text inputs: forwards the target's string `value`.
/// The value→message mapping stays at the browser boundary; `Html` only stores
/// a typed pure id (see `EventSpec::TextInput`).
#cfg(target="js")
extern "js" fn dom_add_value_listener(
  element : DomElement,
  name : String,
  prevent_default : Bool,
  stop_propagation : Bool,
  callback : (String) -> Unit,
) -> Unit =
  #| (element, name, preventDefault, stopPropagation, callback) => {
  #|   element.addEventListener(name, event => {
  #|     if (preventDefault && typeof event.preventDefault === "function") event.preventDefault();
  #|     if (stopPropagation && typeof event.stopPropagation === "function") event.stopPropagation();
  #|     const target = event.target;
  #|     callback(target && target.value != null ? String(target.value) : "");
  #|   });
  #| }

///|
/// DOM-payload listener for keyboard events. Only primitive data crosses the
/// FFI callback; the renderer constructs the typed payload at the boundary.
#cfg(target="js")
extern "js" fn dom_add_key_listener(
  element : DomElement,
  name : String,
  prevent_default : Bool,
  stop_propagation : Bool,
  callback : (String, String, Bool, Bool, Bool, Bool, Bool) -> Int,
) -> Unit =
  #| (element, name, preventDefault, stopPropagation, callback) => {
  #|   element.addEventListener(name, event => {
  #|     if (preventDefault && typeof event.preventDefault === "function") event.preventDefault();
  #|     if (stopPropagation && typeof event.stopPropagation === "function") event.stopPropagation();
  #|     const actionMask = Number(callback(
  #|       event.key == null ? "" : String(event.key),
  #|       event.code == null ? "" : String(event.code),
  #|       !!event.altKey,
  #|       !!event.ctrlKey,
  #|       !!event.metaKey,
  #|       !!event.shiftKey,
  #|       !!event.repeat,
  #|     )) || 0;
  #|     if ((actionMask & 1) !== 0 && typeof event.preventDefault === "function") event.preventDefault();
  #|     if ((actionMask & 2) !== 0 && typeof event.stopPropagation === "function") event.stopPropagation();
  #|   });
  #| }

///|
/// DOM-payload listener for pointer events. Only primitive data crosses the
/// FFI callback; the renderer constructs the typed payload at the boundary.
#cfg(target="js")
extern "js" fn dom_add_pointer_listener(
  element : DomElement,
  name : String,
  prevent_default : Bool,
  stop_propagation : Bool,
  callback : (
    Int,
    String,
    Double,
    Double,
    Double,
    Double,
    Int,
    Int,
    Bool,
    Bool,
    Bool,
    Bool,
  ) -> Unit,
) -> Unit =
  #| (element, name, preventDefault, stopPropagation, callback) => {
  #|   const number = value => {
  #|     const n = Number(value);
  #|     return Number.isFinite(n) ? n : 0;
  #|   };
  #|   element.addEventListener(name, event => {
  #|     if (preventDefault && typeof event.preventDefault === "function") event.preventDefault();
  #|     if (stopPropagation && typeof event.stopPropagation === "function") event.stopPropagation();
  #|     callback(
  #|       Math.trunc(number(event.pointerId)),
  #|       event.pointerType == null ? "" : String(event.pointerType),
  #|       number(event.clientX),
  #|       number(event.clientY),
  #|       number(event.offsetX),
  #|       number(event.offsetY),
  #|       Math.trunc(number(event.button)),
  #|       Math.trunc(number(event.buttons)),
  #|       !!event.altKey,
  #|       !!event.ctrlKey,
  #|       !!event.metaKey,
  #|       !!event.shiftKey,
  #|     );
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
extern "js" fn dom_create_intersection_observer(
  element : DomElement,
  callback : () -> Unit,
) -> Int =
  #| (element, callback) => {
  #|   const store = globalThis.__incrTeaIntersectionObservers ??= new Map();
  #|   const next = (globalThis.__incrTeaIntersectionObserverSeq ?? 0) + 1;
  #|   globalThis.__incrTeaIntersectionObserverSeq = next;
  #|   const observer = new IntersectionObserver(entries => {
  #|     if (entries.some(entry => entry.isIntersecting || entry.intersectionRatio > 0)) {
  #|       callback();
  #|     }
  #|   }, { threshold: 0 });
  #|   observer.observe(element);
  #|   store.set(next, observer);
  #|   return next;
  #| }

///|
#cfg(target="js")
extern "js" fn dom_disconnect_intersection_observer(handle : Int) -> Unit =
  #| (handle) => {
  #|   const store = globalThis.__incrTeaIntersectionObservers;
  #|   const observer = store?.get(handle);
  #|   if (!observer) return;
  #|   observer.disconnect();
  #|   store.delete(handle);
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
  ids.iter().any(tracked => tracked == id)
}

///|
#cfg(target="js")
fn install_render_recompute_counter(
  runtime : @incr.Runtime,
  view_ids : Ref[Array[@incr.CellId]],
  stats : RenderStats,
  view_id_to_label : Ref[Array[(@incr.CellId, String, RenderStats)]],
) -> @incr.ListenerId {
  // Additive listener (#210): mounting the renderer must not clobber any
  // derived-event listener a host integration already installed. The returned
  // ListenerId is stored on the renderer so dispose (#209) can remove it.
  try! runtime.add_derived_event_listener(event => {
    match event {
      @incr.DerivedEvent::Completed(completed) => {
        if view_id_is_tracked(view_ids.val, completed.cell_id) {
          stats.view_recomputes = stats.view_recomputes + 1
        }
        // Route to per-root stats
        for tuple in view_id_to_label.val {
          if tuple.0 == completed.cell_id {
            tuple.2.view_recomputes = tuple.2.view_recomputes + 1
          }
        }
        ()
      }
      _ => ()
    }
  })
}

///|
#cfg(target="js")
priv enum Rendered[Msg] {
  RenderedText(String, DomNode)
  RenderedDirectText(DirectTextId, String, DomNode)
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
    RenderedDirectText(_, _, node) => node
    RenderedElem(element~, ..) => dom_element_node(element)
    RenderedKeyedElem(element~, ..) => dom_element_node(element)
  }
}

///|
/// Mount-boundary payload resolvers. They map typed ids plus browser-extracted
/// payload structs to messages or keyboard event actions (or `None` to ignore
/// them). Executable mapping stays here, outside cacheable `Html` values.
#cfg(target="js")
priv struct PayloadResolvers[Msg] {
  resolve_text : (TextInputId, TextInputPayload) -> Msg?
  resolve_key : (KeyEventId, KeyPayload) -> Msg?
  resolve_pointer : (PointerEventId, PointerPayload) -> Msg?
  resolve_key_event : (KeyEventId, KeyPayload) -> KeyEventDispatch[Msg]?
}

///|
#cfg(target="js")
fn[Msg] PayloadResolvers::PayloadResolvers(
  resolve_text? : (TextInputId, TextInputPayload) -> Msg? = (_, _) => None,
  resolve_key? : (KeyEventId, KeyPayload) -> Msg? = (_, _) => None,
  resolve_pointer? : (PointerEventId, PointerPayload) -> Msg? = (_, _) => None,
  resolve_key_event? : (KeyEventId, KeyPayload) -> KeyEventDispatch[Msg]? = (
    _,
    _,
  ) => None,
) -> PayloadResolvers[Msg] {
  { resolve_text, resolve_key, resolve_pointer, resolve_key_event }
}

///|
/// Mount-boundary direct patch resolvers. `Html` carries only pure ids and
/// fallback values; live watches stay behind these boundary callbacks.
#cfg(target="js")
priv struct DirectPatchResolvers {
  resolve_text : (DirectTextId) -> String?
  resolve_attr : (DirectAttrId) -> String?
}

///|
#cfg(target="js")
fn DirectPatchResolvers::DirectPatchResolvers(
  resolve_text? : (DirectTextId) -> String? = _ => None,
  resolve_attr? : (DirectAttrId) -> String? = _ => None,
) -> DirectPatchResolvers {
  { resolve_text, resolve_attr }
}

///|
#cfg(target="js")
fn DirectPatchResolvers::text_value(
  self : DirectPatchResolvers,
  id : DirectTextId,
  fallback : String,
) -> String {
  match (self.resolve_text)(id) {
    Some(value) => value
    None => fallback
  }
}

///|
#cfg(target="js")
fn DirectPatchResolvers::attr_value(
  self : DirectPatchResolvers,
  attr : Attribute,
) -> String {
  match attr.direct {
    Some(id) =>
      match (self.resolve_attr)(id) {
        Some(value) => value
        None => attr.value
      }
    None => attr.value
  }
}

///|
/// Boundary handle threaded through render/diff so DOM listeners can re-enter
/// the program. `dispatch` forwards fixed messages; payload/action and
/// direct-patch resolvers keep executable boundary state out of cacheable `Html`.
#cfg(target="js")
priv struct EventSink[Msg] {
  dispatch : (Msg) -> Unit
  payload_resolvers : PayloadResolvers[Msg]
  direct_resolvers : DirectPatchResolvers
}

///|
#cfg(target="js")
fn attr_by_name(attrs : Array[Attribute], name : String) -> Attribute? {
  for attr in attrs {
    if attr.name == name {
      break Some(attr)
    }
  } nobreak {
    None
  }
}

///|
#cfg(target="js")
fn patch_attrs(
  tag : String,
  old_attrs : Array[Attribute],
  new_attrs : Array[Attribute],
  element : DomElement,
  direct_resolvers : DirectPatchResolvers,
) -> Unit {
  for old in old_attrs {
    match attr_by_name(new_attrs, old.name) {
      None => dom_remove_attr(element, old.name)
      Some(_) => ()
    }
  }
  for next in new_attrs {
    match attr_by_name(old_attrs, next.name) {
      None => patch_attr(tag, element, next, direct_resolvers)
      Some(prev) =>
        if prev != next {
          patch_attr(tag, element, next, direct_resolvers)
        } else {
          match (prev.direct, next.direct) {
            (None, None) => ()
            _ =>
              if direct_resolvers.attr_value(prev) !=
                direct_resolvers.attr_value(next) {
                patch_attr(tag, element, next, direct_resolvers)
              }
          }
        }
    }
  }
}

///|
#cfg(target="js")
fn patch_attr(
  tag : String,
  element : DomElement,
  attr : Attribute,
  direct_resolvers : DirectPatchResolvers,
) -> Unit {
  set_attr_value(tag, element, attr.name, direct_resolvers.attr_value(attr))
}

///|
#cfg(target="js")
fn set_attr_value(
  tag : String,
  element : DomElement,
  name : String,
  value : String,
) -> Unit {
  dom_set_attr(element, name, value)
  if tag == "input" && name == "value" {
    dom_set_value_property(element, value)
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
  let payload_resolvers = sink.payload_resolvers
  for event in events {
    let actions = event.actions
    match event.spec {
      Const(message) =>
        dom_add_event_listener(
          element,
          event.name,
          actions.prevent_default,
          actions.stop_propagation,
          () => dispatch(message),
        )
      TextInput(id~) =>
        dom_add_value_listener(
          element,
          event.name,
          actions.prevent_default,
          actions.stop_propagation,
          value => {
            match (payload_resolvers.resolve_text)(id, { value, }) {
              Some(message) => dispatch(message)
              None => ()
            }
          },
        )
      Key(id~) =>
        dom_add_key_listener(
          element,
          event.name,
          actions.prevent_default,
          actions.stop_propagation,
          (key, code, alt_key, ctrl_key, meta_key, shift_key, repeat) => {
            let payload : KeyPayload = {
              key,
              code,
              alt_key,
              ctrl_key,
              meta_key,
              shift_key,
              repeat,
            }
            match (payload_resolvers.resolve_key_event)(id, payload) {
              Some(result) => {
                match result.message {
                  Some(message) => dispatch(message)
                  None => ()
                }
                result.action_mask()
              }
              None => {
                match (payload_resolvers.resolve_key)(id, payload) {
                  Some(message) => dispatch(message)
                  None => ()
                }
                0
              }
            }
          },
        )
      Pointer(id~) =>
        dom_add_pointer_listener(
          element,
          event.name,
          actions.prevent_default,
          actions.stop_propagation,
          (
            pointer_id,
            pointer_type,
            client_x,
            client_y,
            offset_x,
            offset_y,
            button,
            buttons,
            alt_key,
            ctrl_key,
            meta_key,
            shift_key,
          ) => {
            let payload : PointerPayload = {
              pointer_id,
              pointer_type,
              client_x,
              client_y,
              offset_x,
              offset_y,
              button,
              buttons,
              alt_key,
              ctrl_key,
              meta_key,
              shift_key,
            }
            match (payload_resolvers.resolve_pointer)(id, payload) {
              Some(message) => dispatch(message)
              None => ()
            }
          },
        )
    }
  }
}

///|
#cfg(target="js")
fn[Msg] render_html(html : Html[Msg], sink : EventSink[Msg]) -> Rendered[Msg] {
  match html.repr {
    Text(value) => RenderedText(value, dom_create_text(value))
    DirectText(id~, fallback~) => {
      let value = sink.direct_resolvers.text_value(id, fallback)
      RenderedDirectText(id, value, dom_create_text(value))
    }
    Elem(tag~, attrs~, events~, children~) => {
      let element = dom_create_element(tag)
      patch_attrs(tag, [], attrs, element, sink.direct_resolvers)
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
      patch_attrs(tag, [], attrs, element, sink.direct_resolvers)
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
  match (old, next.repr) {
    (RenderedText(old_text, node), Text(next_text)) => {
      if old_text != next_text {
        dom_set_text(node, next_text)
      }
      RenderedText(next_text, node)
    }
    (RenderedDirectText(old_id, old_text, node), DirectText(id~, fallback~)) =>
      if old_id != id {
        replace_rendered(old, next, parent, sink)
      } else {
        let next_text = sink.direct_resolvers.text_value(id, fallback)
        if old_text != next_text {
          dom_set_text(node, next_text)
        }
        RenderedDirectText(id, next_text, node)
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
        patch_attrs(
          next_tag,
          old_attrs,
          next_attrs,
          element,
          sink.direct_resolvers,
        )
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
        patch_attrs(
          next_tag,
          old_attrs,
          next_attrs,
          element,
          sink.direct_resolvers,
        )
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
priv struct DirectTextPatch {
  id : DirectTextId
  node : DomNode
  mut last : String
}

///|
#cfg(target="js")
priv struct DirectAttrPatch {
  id : DirectAttrId
  tag : String
  name : String
  element : DomElement
  mut last : String
}

///|
#cfg(target="js")
fn DirectTextPatch::flush(
  self : DirectTextPatch,
  direct_resolvers : DirectPatchResolvers,
) -> Unit {
  let next = direct_resolvers.text_value(self.id, self.last)
  if self.last != next {
    dom_set_text(self.node, next)
    self.last = next
  }
}

///|
#cfg(target="js")
fn DirectAttrPatch::flush(
  self : DirectAttrPatch,
  direct_resolvers : DirectPatchResolvers,
) -> Unit {
  let attr : Attribute = {
    name: self.name,
    value: self.last,
    direct: Some(self.id),
  }
  let next = direct_resolvers.attr_value(attr)
  if self.last != next {
    set_attr_value(self.tag, self.element, self.name, next)
    self.last = next
  }
}

///|
#cfg(target="js")
fn collect_direct_attrs(
  tag : String,
  attrs : Array[Attribute],
  element : DomElement,
  attr_patches : Array[DirectAttrPatch],
  direct_resolvers : DirectPatchResolvers,
) -> Unit {
  for attr in attrs {
    match attr.direct {
      Some(id) =>
        attr_patches.push({
          id,
          tag,
          name: attr.name,
          element,
          last: direct_resolvers.attr_value(attr),
        })
      None => ()
    }
  }
}

///|
#cfg(target="js")
fn[Msg] collect_direct_patches(
  rendered : Rendered[Msg],
  text_patches : Array[DirectTextPatch],
  attr_patches : Array[DirectAttrPatch],
  direct_resolvers : DirectPatchResolvers,
) -> Unit {
  match rendered {
    RenderedText(_, _) => ()
    RenderedDirectText(id, value, node) =>
      text_patches.push({ id, node, last: value })
    RenderedElem(tag~, attrs~, children~, element~, ..) => {
      collect_direct_attrs(tag, attrs, element, attr_patches, direct_resolvers)
      for child in children {
        collect_direct_patches(
          child, text_patches, attr_patches, direct_resolvers,
        )
      }
    }
    RenderedKeyedElem(tag~, attrs~, children~, element~, ..) => {
      collect_direct_attrs(tag, attrs, element, attr_patches, direct_resolvers)
      for pair in children {
        collect_direct_patches(
          pair.1,
          text_patches,
          attr_patches,
          direct_resolvers,
        )
      }
    }
  }
}

///|
#cfg(target="js")
priv struct DirectPatchRoot[Msg] {
  program : Program[Msg, Html[Msg]]
  host : DomElement
  direct_resolvers : DirectPatchResolvers
  mut rendered : Rendered[Msg]?
  mut text_patches : Array[DirectTextPatch]
  mut attr_patches : Array[DirectAttrPatch]
}

///|
#cfg(target="js")
fn[Msg] DirectPatchRoot::DirectPatchRoot(
  program : Program[Msg, Html[Msg]],
  host : DomElement,
  direct_resolvers : DirectPatchResolvers,
) -> DirectPatchRoot[Msg] {
  {
    program,
    host,
    direct_resolvers,
    rendered: None,
    text_patches: [],
    attr_patches: [],
  }
}

///|
#cfg(target="js")
fn[Msg] DirectPatchRoot::event_sink(
  self : DirectPatchRoot[Msg],
) -> EventSink[Msg] {
  {
    dispatch: msg => ignore(self.program.dispatch(msg)),
    payload_resolvers: PayloadResolvers::PayloadResolvers(),
    direct_resolvers: self.direct_resolvers,
  }
}

///|
#cfg(target="js")
fn[Msg] DirectPatchRoot::store_rendered(
  self : DirectPatchRoot[Msg],
  rendered : Rendered[Msg],
) -> Unit {
  self.text_patches = []
  self.attr_patches = []
  collect_direct_patches(
    rendered,
    self.text_patches,
    self.attr_patches,
    self.direct_resolvers,
  )
  self.rendered = Some(rendered)
}

///|
#cfg(target="js")
fn[Msg] DirectPatchRoot::flush_direct_patches(
  self : DirectPatchRoot[Msg],
) -> Unit {
  for patch in self.text_patches {
    patch.flush(self.direct_resolvers)
  }
  for patch in self.attr_patches {
    patch.flush(self.direct_resolvers)
  }
}

///|
#cfg(target="js")
fn[Msg] DirectPatchRoot::flush(self : DirectPatchRoot[Msg]) -> Unit {
  match self.rendered {
    None => {
      let rendered = render_html(
        self.program.read_view_or_abort(),
        self.event_sink(),
      )
      dom_replace_children(self.host, rendered.node())
      self.store_rendered(rendered)
    }
    Some(_) => self.flush_direct_patches()
  }
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
  let common = old_len.min(next_len)
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
/// When the key order is unchanged, children are diffed in place so a local
/// editor-row update does not reparent the focused keyed input. Reorders still
/// append survivors and fresh nodes in new order: `appendChild` on an
/// already-attached node moves it to the end, so replaying the new order
/// left-to-right leaves the parent's children in exactly the new order while
/// reusing each key's DOM node (and its listeners). Removals run first so a
/// vanished node is detached before survivors are re-appended.
///
/// Tradeoff: reordered keyed children are re-appended, so this is not
/// minimal-move (a focused/selected reused node can be reparented on reorder).
/// It only runs when the view value already changed (value-level `Eq` skips
/// unchanged views), and identity is preserved per key. An anchor-based
/// minimal-move pass (LIS / two-ended) is a follow-up if a benchmark or
/// focus-retention need justifies it.
#cfg(target="js")
fn[Msg : Eq] diff_keyed_children(
  old_children : Array[(String, Rendered[Msg])],
  next_children : Array[(String, Html[Msg])],
  parent : DomElement,
  sink : EventSink[Msg],
) -> Array[(String, Rendered[Msg])] {
  let old_keys = old_children.map(pair => pair.0)
  let new_keys = next_children.map(pair => pair.0)
  if old_keys == new_keys {
    next_children.mapi((idx, pair) => {
      let (key, html) = pair
      let child = diff_rendered(old_children[idx].1, html, parent, sink)
      (key, child)
    })
  } else {
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
}

///|
#cfg(target="js")
pub struct BrowserRoot[Msg] {
  priv watched : WatchedHtmlRoot[Msg]
  priv host : DomElement
  // Mount-time boundary resolvers for DOM payload events and keyboard actions.
  // They stay at the browser boundary (never in the cacheable `Html` value);
  // roots without a payload family use defaults that ignore every payload.
  priv payload_resolvers : PayloadResolvers[Msg]
  priv mut rendered : Rendered[Msg]?
  priv mut active : Bool
}

///|
#cfg(target="js")
fn[Msg] BrowserRoot::BrowserRoot(
  program : Program[Msg, Html[Msg]],
  host : DomElement,
  stats : RenderStats,
  label? : String = "",
  resolve_text? : (TextInputId, TextInputPayload) -> Msg? = (_, _) => None,
  resolve_key? : (KeyEventId, KeyPayload) -> Msg? = (_, _) => None,
  resolve_pointer? : (PointerEventId, PointerPayload) -> Msg? = (_, _) => None,
  resolve_key_event? : (KeyEventId, KeyPayload) -> KeyEventDispatch[Msg]? = (
    _,
    _,
  ) => None,
) -> BrowserRoot[Msg] {
  let payload_resolvers = PayloadResolvers::PayloadResolvers(
    resolve_text~,
    resolve_key~,
    resolve_pointer~,
    resolve_key_event~,
  )
  {
    watched: WatchedHtmlRoot::WatchedHtmlRoot(program, stats, label~),
    host,
    payload_resolvers,
    rendered: None,
    active: true,
  }
}

///|
#cfg(target="js")
fn[Msg : Eq] BrowserRoot::flush(self : BrowserRoot[Msg]) -> Unit {
  guard self.watched.read_changed() is Some(next) else { return }
  let sink : EventSink[Msg] = {
    dispatch: msg => ignore(self.watched.program.dispatch(msg)),
    payload_resolvers: self.payload_resolvers,
    direct_resolvers: DirectPatchResolvers::DirectPatchResolvers(),
  }
  self.rendered = Some(
    match self.rendered {
      None => {
        let rendered = render_html(next, sink)
        dom_replace_children(self.host, rendered.node())
        rendered
      }
      Some(old) => diff_rendered(old, next, self.host, sink)
    },
  )
}

///|
#cfg(target="js")
fn[Msg : Eq] BrowserRoot::flush_if_active(self : BrowserRoot[Msg]) -> Unit {
  if self.active {
    self.flush()
  } else {
    let stats = self.watched.stats
    stats.inactive_skipped_flushes = stats.inactive_skipped_flushes + 1
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
fn[Msg] BrowserRoot::drain_after_flush(self : BrowserRoot[Msg]) -> Unit {
  self.watched.program.drain_after_flush()
}

///|
#cfg(target="js")
fn[Msg] BrowserRoot::drain_after_flush_if_active(
  self : BrowserRoot[Msg],
) -> Unit {
  if self.active {
    self.drain_after_flush()
  }
}

///|
#cfg(target="js")
pub struct BrowserRenderer[Msg] {
  priv runtime : @incr.Runtime
  // Mounted roots. Active roots flush on every animation frame; inactive roots
  // stay attached but skip scheduled flush reads until activation.
  priv mut roots : Array[BrowserRoot[Msg]]
  // Detached-but-alive roots (#209): removed from the DOM but their Program is
  // kept so they can be re-attached. The renderer still owns them, so `dispose`
  // tears them down too instead of leaking them.
  priv mut detached : Array[BrowserRoot[Msg]]
  priv stats : RenderStats
  priv view_ids : Ref[Array[@incr.CellId]]
  // Per-root stats mapping for labeled recompute counting.
  priv view_id_to_label : Ref[Array[(@incr.CellId, String, RenderStats)]]
  priv mut frame_scheduled : Bool
  priv after_flush : (RenderStats) -> Unit
  // Lifecycle (#209). The two listener ids are removed on dispose so a torn-down
  // renderer stops reacting to runtime changes and view recomputes. The
  // on_change id is set after construction because its listener closure captures
  // `renderer` itself; it is `None` only during that construction window.
  priv mut disposed : Bool
  priv derived_listener_id : @incr.ListenerId
  priv mut on_change_listener_id : @incr.ListenerId?
}

///|
#cfg(target="js")
pub fn[Msg : Eq] BrowserRenderer::BrowserRenderer(
  runtime : @incr.Runtime,
  after_flush? : (RenderStats) -> Unit = _ => (),
) -> BrowserRenderer[Msg] {
  let stats = RenderStats::RenderStats()
  let view_ids : Ref[Array[@incr.CellId]] = Ref([])
  let view_id_to_label : Ref[Array[(@incr.CellId, String, RenderStats)]] = Ref([])
  let derived_listener_id = install_render_recompute_counter(
    runtime, view_ids, stats, view_id_to_label,
  )
  let renderer = {
    runtime,
    roots: [],
    detached: [],
    stats,
    view_ids,
    view_id_to_label,
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
pub fn[Msg] BrowserRenderer::stats(self : BrowserRenderer[Msg]) -> RenderStats {
  // Build a fresh copy: MoonBit aliases mutable struct fields when assigned
  // (`let total = self.stats` would alias, corrupting renderer state on
  // repeated calls), and `stats()` is called during mount and after every
  // flush cycle. Copy aggregate-only fields from self.stats, then sum per-root
  // patch/skip/inactive counters from all live and detached roots.
  let total = RenderStats::RenderStats()
  total.view_recomputes = self.stats.view_recomputes
  total.frame_flushes = self.stats.frame_flushes
  total.activation_flushes = self.stats.activation_flushes
  // Seed with historic values accumulated from destroyed/disposed roots.
  total.patch_attempts = self.stats.patch_attempts
  total.skipped_patches = self.stats.skipped_patches
  total.inactive_skipped_flushes = self.stats.inactive_skipped_flushes
  // Then sum in per-root counters from still-live roots.
  for root in self.roots {
    let s = root.watched.stats
    total.patch_attempts = total.patch_attempts + s.patch_attempts
    total.skipped_patches = total.skipped_patches + s.skipped_patches
    total.inactive_skipped_flushes = total.inactive_skipped_flushes +
      s.inactive_skipped_flushes
  }
  for root in self.detached {
    let s = root.watched.stats
    total.patch_attempts = total.patch_attempts + s.patch_attempts
    total.skipped_patches = total.skipped_patches + s.skipped_patches
    total.inactive_skipped_flushes = total.inactive_skipped_flushes +
      s.inactive_skipped_flushes
  }
  total
}

///|
#cfg(target="js")
pub fn[Msg : Eq] BrowserRenderer::mount(
  self : BrowserRenderer[Msg],
  host : DomElement,
  program : Program[Msg, Html[Msg]],
  label? : String = "",
  on_input? : (TextInputId, TextInputPayload) -> Msg? = (_, _) => None,
  on_key? : (KeyEventId, KeyPayload) -> Msg? = (_, _) => None,
  on_pointer? : (PointerEventId, PointerPayload) -> Msg? = (_, _) => None,
  on_key_event? : (KeyEventId, KeyPayload) -> KeyEventDispatch[Msg]? = (_, _) => {
    None
  },
) -> BrowserRoot[Msg] {
  guard !self.disposed else {
    abort("BrowserRenderer::mount called after dispose")
  }
  guard program.runtime().id() == self.runtime.id() else {
    abort("BrowserRenderer::mount called with a Program from another Runtime")
  }
  let view_id = program.view_id()
  program.add_after_flush_scheduler(() => self.schedule_flush())
  // One instrumentation id per Program, even if it backs several mounted roots.
  if !view_id_is_tracked(self.view_ids.val, view_id) {
    self.view_ids.val.push(view_id)
  }
  // Register per-root stats for recompute counting — one entry per mount.
  let root_stats = RenderStats::RenderStats()
  self.view_id_to_label.val.push((view_id, label, root_stats))
  let root = BrowserRoot::BrowserRoot(
    program,
    host,
    root_stats,
    label~,
    resolve_text=on_input,
    resolve_key=on_key,
    resolve_pointer=on_pointer,
    resolve_key_event=on_key_event,
  )
  self.roots.push(root)
  root.flush()
  root.drain_after_flush()
  (self.after_flush)(self.stats())
  root
}

///|
/// Per-root labeled stats for locality validation.
pub fn[Msg] BrowserRenderer::root_stats(
  self : BrowserRenderer[Msg],
) -> Array[RootStats] {
  let result : Array[RootStats] = []
  for root in self.roots {
    let s = root.watched.stats
    result.push({
      label: root.watched.label,
      view_recomputes: s.view_recomputes,
      patch_attempts: s.patch_attempts,
      skipped_patches: s.skipped_patches,
    })
  }
  for root in self.detached {
    let s = root.watched.stats
    result.push({
      label: root.watched.label,
      view_recomputes: s.view_recomputes,
      patch_attempts: s.patch_attempts,
      skipped_patches: s.skipped_patches,
    })
  }
  result
}

///|
#cfg(target="js")
fn[Msg : Eq] BrowserRenderer::schedule_flush(
  self : BrowserRenderer[Msg],
) -> Unit {
  guard !self.disposed else { return }
  guard !self.frame_scheduled else { return }
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
      root.flush_if_active()
    }
    self.drain_after_flush_commands()
    (self.after_flush)(self.stats())
  })
  if queued {
    self.frame_scheduled = true
  }
}

///|
#cfg(target="js")
fn[Msg] BrowserRenderer::drain_after_flush_commands(
  self : BrowserRenderer[Msg],
) -> Unit {
  guard !self.disposed else { return }
  for root in self.roots {
    root.drain_after_flush_if_active()
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

///| Preserves a root's per-root patch/skip/inactive counters into the

///| renderer-level aggregate before the root's RenderStats goes out of scope.

///| Used by destroy() and dispose() so that renderer.stats() remains monotonic

///|
/// — destroyed roots' work is not lost when their arrays are cleared.
#cfg(target="js")
fn[Msg] BrowserRenderer::accumulate_stats(
  self : BrowserRenderer[Msg],
  root : BrowserRoot[Msg],
) -> Unit {
  let s = root.watched.stats
  self.stats.patch_attempts = self.stats.patch_attempts + s.patch_attempts
  self.stats.skipped_patches = self.stats.skipped_patches + s.skipped_patches
  self.stats.inactive_skipped_flushes = self.stats.inactive_skipped_flushes +
    s.inactive_skipped_flushes
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
/// Marks a mounted root inactive without detaching its DOM or disposing its
/// Program. Scheduled renderer frames keep ownership and post-dispose teardown,
/// but skip `root.flush()` until `activate` performs a catch-up read.
#cfg(target="js")
pub fn[Msg] BrowserRenderer::deactivate(
  self : BrowserRenderer[Msg],
  root : BrowserRoot[Msg],
) -> Unit {
  guard !self.disposed else { return }
  guard self.roots.iter().any(other => physical_equal(other, root)) else {
    return
  }
  root.active = false
}

///|
/// Marks a mounted inactive root active and performs one catch-up flush while
/// its DOM, Program, and view Watch are still the same objects.
#cfg(target="js")
pub fn[Msg : Eq] BrowserRenderer::activate(
  self : BrowserRenderer[Msg],
  root : BrowserRoot[Msg],
) -> Unit {
  guard !self.disposed else { return }
  guard self.roots.iter().any(other => physical_equal(other, root)) else {
    return
  }
  guard !root.active else { return }
  root.active = true
  self.stats.activation_flushes = self.stats.activation_flushes + 1
  root.flush()
  root.drain_after_flush()
  (self.after_flush)(self.stats())
}

///|
/// Example-local manual-first activation policy helper for mounted inactive
/// roots.
///
/// Product/semantic UI actions should call `show` before a root becomes
/// interactive and `hide` when it becomes non-interactive. `prewarm` is only an
/// advisory early `show`: it uses the same activation path, including the
/// catch-up flush and after-flush drain, so call it only when those early effects
/// are acceptable for that root.
#cfg(target="js")
pub struct BrowserRootActivationController[Msg] {
  priv renderer : BrowserRenderer[Msg]
}

///|
/// Creates a policy helper that shares the underlying renderer object. Callers
/// keep their `BrowserRenderer` reference for mounting, stats, and disposal.
#cfg(target="js")
pub fn[Msg] BrowserRootActivationController::BrowserRootActivationController(
  renderer : BrowserRenderer[Msg],
) -> BrowserRootActivationController[Msg] {
  { renderer, }
}

///|
/// Semantic hide for a mounted root. The DOM and `Program` remain attached, but
/// scheduled renderer frames skip the watched-view read until `show` or
/// `prewarm` activates the root.
#cfg(target="js")
pub fn[Msg] BrowserRootActivationController::hide(
  self : BrowserRootActivationController[Msg],
  root : BrowserRoot[Msg],
) -> Unit {
  self.renderer.deactivate(root)
}

///|
/// Semantic show for a mounted root. This marks the root active and performs the
/// renderer catch-up flush before callers let the root become interactive.
#cfg(target="js")
pub fn[Msg : Eq] BrowserRootActivationController::show(
  self : BrowserRootActivationController[Msg],
  root : BrowserRoot[Msg],
) -> Unit {
  self.renderer.activate(root)
}

///|
/// Advisory prewarm for roots where early activation side effects are safe.
///
/// This intentionally reuses `show` rather than adding a side-effect-free
/// scheduler path: it marks the root active, catches up the DOM, and drains
/// after-flush commands. A later semantic `show` is then a no-op unless the root
/// was hidden again.
#cfg(target="js")
pub fn[Msg : Eq] BrowserRootActivationController::prewarm(
  self : BrowserRootActivationController[Msg],
  root : BrowserRoot[Msg],
) -> Unit {
  // Intent only: prewarm is the same side-effecting activation as show.
  self.show(root)
}

///|
/// Detaches a mounted root: removes its DOM subtree but keeps the Program alive,
/// and parks the root so a later rAF will not re-render it. The renderer still
/// owns it (so `dispose` reclaims it); re-attach with `reattach`. No-op if `root`
/// is not currently mounted.
#cfg(target="js")
pub fn[Msg] BrowserRenderer::detach(
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
pub fn[Msg : Eq] BrowserRenderer::reattach(
  self : BrowserRenderer[Msg],
  root : BrowserRoot[Msg],
) -> Unit {
  guard !self.disposed else { return }
  guard self.detached.iter().any(other => physical_equal(other, root)) else {
    return
  }
  self.detached = self.detached.filter(other => !physical_equal(other, root))
  root.active = true
  self.roots.push(root)
  root.flush()
  root.drain_after_flush()
  (self.after_flush)(self.stats())
}

///|
/// Destroys a single root — mounted or detached: tears down its DOM, removes it
/// from both buckets, and disposes the Program when no sibling root still
/// references it, so destroying one of several mounts of a shared component
/// leaves the others working. The instrumentation id is dropped on the same
/// last-reference condition.
#cfg(target="js")
pub fn[Msg] BrowserRenderer::destroy(
  self : BrowserRenderer[Msg],
  root : BrowserRoot[Msg],
) -> Unit {
  guard self.roots.iter().any(other => physical_equal(other, root)) ||
    self.detached.iter().any(other => physical_equal(other, root)) else {
    return
  }
  root.detach()
  // Preserve per-root counters into the renderer aggregate before removal.
  self.accumulate_stats(root)
  self.remove_root(root)
  // Remove this root's entry from the recompute fan-out map.
  // physical_equal on the RenderStats identifies this mount's entry.
  let root_stats = root.watched.stats
  self.view_id_to_label.val = self.view_id_to_label.val.filter(fn(pair) {
    !physical_equal(pair.2, root_stats)
  })
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
pub fn[Msg] BrowserRenderer::dispose(self : BrowserRenderer[Msg]) -> Unit {
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
  // Preserve per-root counters into the renderer aggregate before arrays are
  // cleared, so renderer.stats() reports historic totals after dispose.
  for root in mounted {
    self.accumulate_stats(root)
  }
  for root in parked {
    self.accumulate_stats(root)
  }
  self.roots = []
  self.detached = []
  for root in mounted {
    root.destroy()
  }
  for root in parked {
    root.destroy()
  }
  self.view_ids.val = []
  self.view_id_to_label.val = []
}
