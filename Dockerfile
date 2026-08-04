FROM elixir:1.16-otp-26-alpine

RUN mix local.hex --force && mix local.rebar --force

WORKDIR /kore
COPY mix.exs mix.lock* ./
COPY lib/ lib/
COPY priv/ priv/
RUN mix deps.get && mix compile && mix escript.build

ENV PATH="/kore:${PATH}"

WORKDIR /app
ENTRYPOINT ["kore"]
CMD ["help"]
