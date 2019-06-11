# Proposed System Changes

## Database Migration
The current running database is a MySQL server storing around 400,000 data points. With the proposed changes
below, this dataset will be converted to a PostgreSQL server storing just over half of these points in a more efficient
and more secure manner.

[Storage Formats](#Storage-Formats)

[Organization and Validation](#Organization-and-Validation)

> [Flight Stitching](#Flight-Stitching)

> [Validation at Conversion](#Validation-at-Conversion)

> [Validation after Conversion](#Validation-after-Conversion)

[Security](#Security)

### PostgreSQL
Why the switch? The SQL type will be changed to PostgreSQL for a number of reasons:
- It's fully ACID (**A**tomicity, **C**onsistenscy, **I**solation, and **D**urability) compliant. What does this mean?
  From the ground up, it ensures the integrity of all parts of each transaction, it verifies all data in a
  transaction before committing, it ensures all concurrent queries take place in a consistent order, and all
  completed transactions will be safe in the event of a system outage. These traits allow the server to perform well
  under heavy loads, with or without a server cluster.
- It's more compliant with the 2011 SQL standards
- It works well under heavy reads/writes and complex queries
- It has a strong development community
- It can store and index json data
- Geospatial data support comes built-in
- It's completely open-source 

### Storage Formats
The current dataset is stored in one table with 14 column values:

| Value             | Type        | Description                                              | Example           |
|-------------------|-------------|----------------------------------------------------------|-------------------|
| Primary Key       | integer     | Auto-incrementing primary key                            | 1                 |
| Actual/Test       | char        | 'A' or 'T', indicates whether a flight was deemed a test | 'T'               |
| Date              | date object | The date of the flight as an optimized object            | Date(2018, 8, 7)  |
| Time              | string      | The time in string form as it was received               | "17:55:04"        |
| Date              | string      | The date in string form as it was received               | "2018-8-7"        |
| Latitude          | string      | Latitude of point                                        | "-114.56"         |
| Longitude         | string      | Longitude of point                                       | "80.822"          |
| Altitude          | string      | Altitude of point with written-form commas               | "5,789"           |
| Vertical Velocity | decimal     | Vertical velocity calculated by GPS                      | -11.0             |
| Ground Speed      | decimal     | Magnitude of ground velocity calculated by GPS           | 3.2               |
| Satellites        | integer     | Number of satellites tracked by Iridium modem            | 4                 |
| Course            | decimal     | Direction of ground velocity calculated by GPS           | 115.3             |
| State             | integer     | Not clear, likely acknowledging a command                | 1                 |
| IMEI              | string      | Identification number                                    | "300234060252680" |

Several things here can be improved:

- Several numerical values are stored in string form and may be converted to integer or decimal objects for speed
  and storage optimization.
- While introduced with good intentions, the `Actual/Test` field most often is not used by the client, as it must be
  manually differentiated on server-side via the command line. Instead, tools to automatically or manually erase
  unneeded flights after their completion may be provided to the client within ground station or tracking software.
- The current dataset differentiates flights solely by `Date (object)` and `IMEI`, allowing several continuous flights
  to be split apart by midnight in UTC. To fix this, a single standardized ID grouping all data points within a
  particular flight may be implemented to reduce confusion and increase search speed. A convenient metric for a flight
  is the date it was started on.
- Many points currently share the same two or three values. In particular, many points will share both `Date` values and
  the `IMEI`. This results in a lot of wasted space and may be remedied by consolidating these three values to a single
  uniform ID.
- In present single-table form,the only way to obtain a list of all unique IMEIs or flights for requesting software
  is to create a query on all 400,000 points. To create faster query speeds and a more useful catalog of current flights,
  a second table relating start date, IMEI and the uniform ID may be constructed and maintained alongside the main
  table.

#### Proposed Changes

Taking the current problems into account, the new proposed dataset stores flights listings in one 3-column table:

| Value      | Type      | Description                                  | Example                              |
|------------|-----------|----------------------------------------------|--------------------------------------|
| UID        | snowflake | Primary key encoded with start date and IMEI | 237666042108680                      |
| Start Date | timestamp | The date and time of this flight point       | "2013-6-14 18:22:01" (stored as int) |
| IMEI       | integer   | Identification number                        | 300234060252680                      |

Accompanying this is the main data table with 9 columns:

| Value             | Type      | Description                                   | Example                              |
|-------------------|-----------|-----------------------------------------------|--------------------------------------|
| Primary Key       | integer   | Auto-incrementing primary key                 | 2                                    |
| UID               | snowflake | Primary key encoded with start date and IMEI  | 237666042108680                      |
| Datetime          | timestamp | The date and time of this flight point        | "2013-6-14 18:22:01" (stored as int) |
| Latitude          | double    | The latitude of this flight point             | -114.56                              |
| Longitude         | double    | The longitude of this flight point            | 80.822                               |
| Altitude          | float     | The altitude of this flight point             | 5789.0                               |
| Vertical Velocity | float     | The vertical velocity calculated by the GPS   | -11.0                                |
| Ground Speed      | float     | The surface speed calculated by the GPS       | 3.2                                  |
| Satellites        | integer   | Number of satellites tracked by Iridium modem | 4                                    |

The reasons for creating/keeping each field in the main table are as follows:

- **Primary Key:** Because the UID here is being used to group data points, it will not be unique across all rows, so
  a standard incrementing integer differentiates unique rows.
- **UID:** This ID is a `Snowflake` encoded with both the start date and imei of each associated flight. This allows
  easy grouping and fast searching of flights.
- **Datetime:** This timestamp contains the exact date and time of this specific flight point, stored in unix
  timestamp form.
- **Latitude/Longitude:** Coordinates now stored in numeric form
- **Altitude:** Altitude in meters
- **Vertical Velocity:** Useful for comparing with location/time while doing calculations
- **Ground Velocity:** More data verification
- **Satellites:** Useful in mobile data debugging

### Organization and Validation

The old dataset comes with a few key problems:
- Points are not grouped together by flight, but by date
- Many points are erroneous or useless
- There exist no checks for validating new data or tools for filtering old data

#### Flight Stitching
In order to stitch together the instances of flights being spread out over two days (or more), the following code
from `db_conversions.py` is used:

```python
def merge_crossovers():
    total = 0
    removable = []
    print('Beginning merge...')
    for f in flights:
        if flights[f]:
            first = flights[f][0]
            fdate = dt.fromtimestamp(first.timestamp)
            if fdate.hour == 0 and fdate.minute < 59:
                yesterday = first.start_date - timedelta(days=1)
                if (yesterday, first.imei) in flights:
                    found = flights[(yesterday, first.imei)]
                    last = found[-1]
                    ldate = dt.fromtimestamp(last.timestamp)
                    if ldate.hour == 23:
                        found += flights[f]
                        removable.append(f)
                        total += 1
    for f in removable:
        del flights[f]

    print('Made {} merges'.format(total))
    print('Flight list reduced to {} flights'.format(len(flights)))
```
Here, `flights` is a dictionary of `(start_date, imei)` tuples used as keys for lists of `FlightPoint`s built from
the original dataset. Before merging, all flights are grouped only by date and time, and all `FlightPoint`s are
sorted by timestamp.

Though a bit messy, the code completes the following sequence for every flight. It first examines the time of the
earliest point in the flight. If the time is less than 1 am, it then checks for a flight with the same IMEI on the
previous date, and, if found, checks if the time of the latest point is at least 11 pm. If all conditions are met, it
appends the later flight points to the earlier points and removes the instance of the later flight.

As this code is used in a one-time process, it was not optimized for readability, so apologies for that. It does, however,
effectively merge a little over 100 flights at the time of this writing.

#### Validation at Conversion

Several validation issues occur at conversion: many flights have erroneous IMEIs, many flights all occur at ground level
and are therefore not real, and some flight points are recorded below sea level.

Two filters are employed to combat these
issues. For flights, we use:
```python
def valid_flight(flight):
    """ A check for flights to actually save

    `flight[1]` is the IMEI and should begin with 3.
    5000 meters is a good metric for a real flight
    """
    if str(flight[1]).startswith('3'):
        for p in flights[flight]:
            if p.altitude >= 5000:
                return True
    return False
```
And for points,
```python
def valid_point(point):
    """ A check for points to actually save
    """
    if point.altitude > 0:
        return True
    return False
```
The pair are used to verify data in `register_flights` and `migrate_points` from the module `db_conversions.py`.

#### Validation after Conversion

To verify new data, database CHECKs are implemented to safeguard the dataset from erroneous transactions. The full
list of checks may be seen in the included sql files.

These checks serve primarily as safeguards, and client-side validation should still be exercised on all incoming data.

Client tools for filtering and removing unwanted flights will also come packaged in the Aurora Tracker platform.

### Security

The current MySQL server has a port open to the network and (supposedly) is accessed by the current Borealis website
and written to by the DirectoryWatcher server. This means there is pure SQL floating around between at least two
connections.

To reduce the possibility of SQL injection or related database corruption attacks, all data will now be stored and
and served by the Gaia Core Server which will be hosted on the same virtual machine as the database. This Express.js
server will process http queries, pull and package data, and return results in json or xml format. It will also handle
row entries and csv requests. This system will allow a SQL-free read and write process which will both make data
more accessible and minimize the potential security risk an open database would pose. The PostgreSQL server won't need
a single port on the network and can be accessed purely within the machine scope.
