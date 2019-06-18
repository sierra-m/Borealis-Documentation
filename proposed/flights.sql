-- Table: public.flights

-- DROP TABLE public.flights;

CREATE TABLE public.flights
(
    primary_key bigint NOT NULL DEFAULT nextval('flights_primary_key_seq'::regclass),
    uid bigint NOT NULL,
    datetime timestamp without time zone NOT NULL,
    latitude double precision NOT NULL,
    longitude double precision NOT NULL,
    altitude real NOT NULL,
    vertical_velocity real NOT NULL,
    ground_speed real NOT NULL,
    satellites smallint,
    CONSTRAINT flights_pkey PRIMARY KEY (primary_key),
    CONSTRAINT "Datetime Valid" CHECK (datetime > '2013-01-01 00:00:00'::timestamp without time zone),
    CONSTRAINT "Altitude Positive" CHECK (altitude > 0::double precision),
    CONSTRAINT "Ground Speed Positive" CHECK (ground_speed >= 0::double precision),
    CONSTRAINT "Satellites Positive" CHECK (satellites >= 0)
)
WITH (
    OIDS = FALSE
)
TABLESPACE pg_default;

ALTER TABLE public.flights
    OWNER to "Aurora";
COMMENT ON TABLE public.flights
    IS 'Flight points repository. Flights are grouped entirely by UID and as such should be queried that way';
