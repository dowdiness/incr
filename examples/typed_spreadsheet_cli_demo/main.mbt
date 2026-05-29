///|
priv enum OutputFormat {
  TextFormat
  JsonFormat
}

///|
fn main {
  println(render_cli())
}

///|
fn render_cli(argv? : Array[String]) -> String {
  let command = scenario_command()
  match parse_matches(command, argv) {
    Ok(matches) =>
      match parse_output_format(matches) {
        Ok(format) => render_scenario(format)
        Err(message) => render_cli_error(command, message)
      }
    Err(message) => message
  }
}

///|
fn scenario_command() -> @argparse.Command {
  Command(
    "typed-spreadsheet-demo",
    about="Run the fixed typed spreadsheet operation scenario.",
    options=[
      OptionArg("format", short='f', about="Output format: text or json.", default_values=[
        "text",
      ]),
    ],
  )
}

///|
fn parse_matches(
  command : @argparse.Command,
  argv : Array[String]?,
) -> Result[@argparse.Matches, String] {
  let matches = match argv {
    Some(values) =>
      command.parse(argv=values, env={}) catch {
        err => return Err(err.to_string())
      }
    None => command.parse() catch { err => return Err(err.to_string()) }
  }
  Ok(matches)
}

///|
fn parse_output_format(
  matches : @argparse.Matches,
) -> Result[OutputFormat, String] {
  match matches.values.get("format") {
    Some(["text"]) => Ok(TextFormat)
    Some(["json"]) => Ok(JsonFormat)
    Some([value]) =>
      Err("unsupported --format '\{value}' (expected text or json)")
    Some(values) => {
      let count = values.length()
      Err("expected one --format value, got \{count}")
    }
    None => Ok(TextFormat)
  }
}

///|
fn render_cli_error(command : @argparse.Command, message : String) -> String {
  let buffer = StringBuilder()
  write_line(buffer, "error: \{message}")
  write_line(buffer, "")
  buffer.write_string(command.render_help())
  buffer.to_string()
}

///|
fn render_scenario(format : OutputFormat) -> String {
  let steps = run_scenario()
  match format {
    TextFormat => render_text(steps)
    JsonFormat => render_json(steps)
  }
}
