use std::{any::Any, collections::HashMap};

use prost::{DecodeError, Message};

pub trait TypeUrl {
    const TYPE_URL: &'static str;
}

pub trait AnyMessage: Message {
    fn as_any(&self) -> &dyn Any;
}

impl<T: Message + Default + Sized + 'static> AnyMessage for T {
    fn as_any(&self) -> &dyn Any {
        self
    }
}

type DecodeBoxedFn =
    Box<dyn Fn(&[u8]) -> Result<Box<dyn AnyMessage>, DecodeError> + Sync + Send + 'static>;

#[static_init::dynamic]
static mut REGISTRY: HashMap<&'static str, DecodeBoxedFn> = HashMap::new();

pub fn register_message<M>()
where
    M: AnyMessage + TypeUrl + Default + 'static,
{
    if let Some((_, t)) = M::TYPE_URL.split_once('/') {
        REGISTRY.write().insert(
            t,
            Box::new(|b| M::decode(b).map(|v| Box::new(v) as Box<dyn AnyMessage>)),
        );
    } else {
        panic!("malformed type url: {:?}", M::TYPE_URL);
    }
}

pub fn pack<M>(msg: M) -> pbjson_types::Any
where
    M: AnyMessage + TypeUrl,
{
    pbjson_types::Any {
        type_url: M::TYPE_URL.to_owned(),
        value: msg.encode_to_vec().into(),
    }
}

pub fn unpack(any: pbjson_types::Any) -> Result<Box<dyn AnyMessage>, prost::DecodeError> {
    let t = any
        .type_url
        .split_once('/')
        .map(|s| s.1)
        .unwrap_or_default();
    if let Some(decode_fn) = REGISTRY.read().get(&t) {
        decode_fn(&any.value)
    } else {
        Err(DecodeError::new(format!(
            "unknown message type {:?}",
            any.type_url
        )))
    }
}
