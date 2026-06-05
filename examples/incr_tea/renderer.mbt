///|
/// Mutable instrumentation counters for mounted watched HTML roots.
#cfg(target="js")
priv struct RenderStats {
  mut view_recomputes : Int
  mut patch_attempts : Int
  mut skipped_patches : Int
  mut frame_flushes : Int
}

///|
#cfg(target="js")
fn RenderStats::RenderStats() -> RenderStats {
  {
    view_recomputes: 0,
    patch_attempts: 0,
    skipped_patches: 0,
    frame_flushes: 0,
  }
}

///|
#cfg(target="js")
priv struct WatchedHtmlRoot[Msg] {
  program : Program[Msg, Html[Msg]]
  stats : RenderStats
  mut last_view : Html[Msg]?
}

///|
#cfg(target="js")
fn[Msg] WatchedHtmlRoot::WatchedHtmlRoot(
  program : Program[Msg, Html[Msg]],
  stats : RenderStats,
) -> WatchedHtmlRoot[Msg] {
  { program, stats, last_view: None }
}

///|
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
