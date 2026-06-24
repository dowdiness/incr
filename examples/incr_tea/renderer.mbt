///|
/// Mutable instrumentation counters for mounted watched HTML roots.
#cfg(target="js")
pub struct RenderStats {
  priv mut view_recomputes : Int
  priv mut patch_attempts : Int
  priv mut skipped_patches : Int
  priv mut frame_flushes : Int
  priv mut inactive_skipped_flushes : Int
  priv mut activation_flushes : Int
}

///|
#cfg(target="js")
pub fn RenderStats::RenderStats() -> RenderStats {
  {
    view_recomputes: 0,
    patch_attempts: 0,
    skipped_patches: 0,
    frame_flushes: 0,
    inactive_skipped_flushes: 0,
    activation_flushes: 0,
  }
}

///|
/// Number of mounted view-root recomputes observed by renderer instrumentation.
pub fn RenderStats::view_recomputes(self : RenderStats) -> Int {
  self.view_recomputes
}

///|
/// Number of DOM patch attempts performed for changed `Html` values.
pub fn RenderStats::patch_attempts(self : RenderStats) -> Int {
  self.patch_attempts
}

///|
/// Number of flush reads skipped because the `Html` value was unchanged.
pub fn RenderStats::skipped_patches(self : RenderStats) -> Int {
  self.skipped_patches
}

///|
/// Number of animation-frame flush callbacks completed by the renderer.
pub fn RenderStats::frame_flushes(self : RenderStats) -> Int {
  self.frame_flushes
}

///|
/// Number of mounted roots skipped because they were marked inactive.
pub fn RenderStats::inactive_skipped_flushes(self : RenderStats) -> Int {
  self.inactive_skipped_flushes
}

///|
/// Number of catch-up flushes performed when inactive roots were activated.
pub fn RenderStats::activation_flushes(self : RenderStats) -> Int {
  self.activation_flushes
}

///| Per-root named counters returned by `BrowserRenderer::root_stats()`.
///| `view_recomputes` is incremented when the root's view Derived re-evaluates.
///| `patch_attempts` and `skipped_patches` are per-root DOM patch/skip counters.
#cfg(target="js")
pub(all) struct RootStats {
  label : String
  view_recomputes : Int
  patch_attempts : Int
  skipped_patches : Int
}
///| Accumulates another RenderStats into this one (addition).
#cfg(target="js")
pub fn RenderStats::add(self : RenderStats, other : RenderStats) -> RenderStats {
  {
    view_recomputes: self.view_recomputes + other.view_recomputes,
    patch_attempts: self.patch_attempts + other.patch_attempts,
    skipped_patches: self.skipped_patches + other.skipped_patches,
    frame_flushes: self.frame_flushes + other.frame_flushes,
    inactive_skipped_flushes: self.inactive_skipped_flushes + other.inactive_skipped_flushes,
    activation_flushes: self.activation_flushes + other.activation_flushes,
  }
}

#cfg(target="js")
priv struct WatchedHtmlRoot[Msg] {
  program : Program[Msg, Html[Msg]]
  label : String
  stats : RenderStats
  mut last_view : Html[Msg]?
}

#cfg(target="js")
fn[Msg] WatchedHtmlRoot::WatchedHtmlRoot(
  program : Program[Msg, Html[Msg]],
  stats : RenderStats,
  label? : String = "",
) -> WatchedHtmlRoot[Msg] {
  { program, label, stats, last_view: None }
}

#cfg(target="js")
fn[Msg : Eq] WatchedHtmlRoot::read_changed(
  self : WatchedHtmlRoot[Msg],
) -> Html[Msg]? {
  guard self.program.read_view() is Some(next) else { return None }
  match self.last_view {
    Some(prev) =>
      if prev == next {
        self.stats.skipped_patches = self.stats.skipped_patches + 1
        None
      } else {
        self.stats.patch_attempts = self.stats.patch_attempts + 1
        self.last_view = Some(next)
        Some(next)
      }
    None => {
      self.stats.patch_attempts = self.stats.patch_attempts + 1
      self.last_view = Some(next)
      Some(next)
    }
  }
}
