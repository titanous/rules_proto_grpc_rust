use std::io::{self, Read, Write};

use prost::Message;
use prost_types::compiler::CodeGeneratorRequest;
use protoc_gen_prost::{Generator, GeneratorResultExt, ModuleRequestSet};

use generator::AnyGenerator;

mod generator;

/// Execute the core _Prost!_ generator from a raw [`CodeGeneratorRequest`]
pub fn execute(raw_request: &[u8]) -> protoc_gen_prost::Result {
    let request = CodeGeneratorRequest::decode(raw_request)?;

    let module_request_set = ModuleRequestSet::new(
        request.file_to_generate,
        request.proto_file,
        raw_request,
        None,
    )?;

    let files = AnyGenerator::new().generate(&module_request_set)?;

    Ok(files)
}

fn main() -> io::Result<()> {
    let mut buf = Vec::new();
    io::stdin().read_to_end(&mut buf)?;

    let response = execute(buf.as_slice()).unwrap_codegen_response();

    buf.clear();
    response.encode(&mut buf).expect("error encoding response");
    io::stdout().write_all(&buf)?;

    Ok(())
}
