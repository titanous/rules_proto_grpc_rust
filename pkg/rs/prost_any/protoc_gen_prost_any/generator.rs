use std::io::Write as _;
use std::iter;
use std::process::{Command, Stdio};

use anyhow::{bail, Context as _, Result};
use heck::ToSnakeCase as _;
use proc_macro2::TokenStream;
use prost_types::{compiler::code_generator_response::File, DescriptorProto};
use protoc_gen_prost::{Generator, ModuleRequestSet};
use quote::quote;
use runfiles::Runfiles;

pub struct AnyGenerator {}

fn map_msg(
    m: DescriptorProto,
    name_prefix: String,
    type_prefix: String,
) -> Box<dyn Iterator<Item = (String, String)>> {
    let prefixed_name = format!("{}.{}", name_prefix, m.name());

    Box::new(
        iter::once((
            format!("{}{}", type_prefix, m.name()),
            format!("/{}", prefixed_name),
        ))
        .chain(
            m.nested_type
                .clone()
                .into_iter()
                .filter(|nm| {
                    !nm.options
                        .as_ref()
                        .and_then(|options| options.map_entry)
                        .unwrap_or(false)
                })
                .flat_map(move |nm| {
                    map_msg(
                        nm,
                        prefixed_name.clone(),
                        format!("{}{}::", type_prefix, to_snake(m.name())),
                    )
                }),
        ),
    )
}

impl Generator for AnyGenerator {
    fn generate(&mut self, module_request_set: &ModuleRequestSet) -> protoc_gen_prost::Result {
        module_request_set
            .requests()
            .map(|(_, request)| {
                let type_names_and_uris: Vec<(String, String)> = request
                    .files()
                    .flat_map(|f| {
                        f.message_type.clone().into_iter().flat_map(|m| {
                            map_msg(m, f.package.clone().unwrap_or_default(), "".to_string())
                        })
                    })
                    .collect();

                let type_names = type_names_and_uris
                    .iter()
                    .map(|t| t.0.parse::<TokenStream>().unwrap());
                let register_names = type_names.clone();
                let type_urls = type_names_and_uris.iter().map(|t| t.1.clone());

                let tokens = quote! {
                    // @generated

                    #(impl ::prost_any::TypeUrl for #type_names {
                        const TYPE_URL: &'static str = #type_urls;
                    })*

                    #[static_init::constructor]
                    extern "C" fn register_any() {
                        #(::prost_any::register_message::<#register_names>();)*
                    }
                };

                let output_filename = format!("{}.any.rs", request.proto_package_name());

                Ok(File {
                    name: Some(output_filename),
                    content: Some(rustfmt(tokens.to_string())?),
                    ..File::default()
                })
            })
            .collect()
    }
}

impl AnyGenerator {
    pub fn new() -> Self {
        Self {}
    }
}

/// Converts a `camelCase` or `SCREAMING_SNAKE_CASE` identifier to a `lower_snake` case Rust field
/// identifier.
fn to_snake(s: &str) -> String {
    let mut ident = s.to_snake_case();

    // Use a raw identifier if the identifier matches a Rust keyword:
    // https://doc.rust-lang.org/reference/keywords.html.
    match ident.as_str() {
        // 2015 strict keywords.
        | "as" | "break" | "const" | "continue" | "else" | "enum" | "false"
        | "fn" | "for" | "if" | "impl" | "in" | "let" | "loop" | "match" | "mod" | "move" | "mut"
        | "pub" | "ref" | "return" | "static" | "struct" | "trait" | "true"
        | "type" | "unsafe" | "use" | "where" | "while"
        // 2018 strict keywords.
        | "dyn"
        // 2015 reserved keywords.
        | "abstract" | "become" | "box" | "do" | "final" | "macro" | "override" | "priv" | "typeof"
        | "unsized" | "virtual" | "yield"
        // 2018 reserved keywords.
        | "async" | "await" | "try" => ident.insert_str(0, "r#"),
        // the following keywords are not supported as raw identifiers and are therefore suffixed with an underscore.
        "self" | "super" | "extern" | "crate" => ident += "_",
        _ => (),
    }
    ident
}

fn rustfmt(content: String) -> Result<String> {
    let rustfmt = Runfiles::create().unwrap().rlocation(env!("RUSTFMT"));
    if !rustfmt.exists() {
        bail!("rustfmt does not exist at: {}", rustfmt.display());
    }

    let mut child = Command::new(&rustfmt)
        .arg("--edition")
        .arg("2021")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .context("failed to run rustfmt")?;

    let mut stdin = child.stdin.take().context("failed to open rustfmt stdin")?;
    std::thread::spawn(move || {
        stdin
            .write_all(content.as_bytes())
            .expect("Failed to write to rustfmt stdin");
    });

    let output = child
        .wait_with_output()
        .context("failed to read rustfmt stdout")?;

    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}
