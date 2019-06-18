-- Table: public."flight-registry"

-- DROP TABLE public."flight-registry";

CREATE TABLE public."flight-registry"
(
    uid bigint NOT NULL,
    start_date date NOT NULL,
    imei bigint NOT NULL,
    CONSTRAINT "flight-registry_pkey" PRIMARY KEY (uid),
    CONSTRAINT "UID Valid" CHECK (uid >= '11596411699200'::bigint),
    CONSTRAINT "Date Valid" CHECK (start_date > '2013-01-01'::date),
    CONSTRAINT "IMEI Valid" CHECK (imei > '300000000000000'::bigint)
)
WITH (
    OIDS = FALSE
)
TABLESPACE pg_default;

ALTER TABLE public."flight-registry"
    OWNER to "Aurora";
COMMENT ON TABLE public."flight-registry"
    IS 'Central flight data repository. Rows represent physical flights, where a flight is a collection of data points. The flight''s Unique Identifier (UID) is calculated from the IMEI and start date, so this table is not necessary to a user that knows a flight already exists.';

COMMENT ON CONSTRAINT "UID Valid" ON public."flight-registry"
    IS 'The UID must be at least the value corresponding to 2013-01-02 with IMEI substring "0000000"';
