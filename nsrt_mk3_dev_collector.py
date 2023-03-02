import logging
import nsrt_mk3_dev
import os
import pytz
import re
import time

from datetime import datetime
from logging.handlers import TimedRotatingFileHandler
from shell import shell

#####################################################################
# Settings

DEVICE_REGEX = "usb-Convergence_Instruments_NSRT_mk3_Dev-*"
WEIGHTING = nsrt_mk3_dev.NsrtMk3Dev.Weighting.DB_C
TIMEZONE = "America/Los_Angeles"
LOGFILENAME = "decible_measurements.csv"
LOGDIR = "measurements"

#######################################
# Locate and open the sound meter device

DEVICE = shell(f"find /dev/serial -name {DEVICE_REGEX}").output()[0]
assert len(DEVICE) > 0, f"Unable to find device with REGEX[{DEVICE_REGEX}]"
nsrt = nsrt_mk3_dev.NsrtMk3Dev(DEVICE)

#######################################
# Read metadata

model = nsrt.read_model()
serial_number = nsrt.read_sn()
firmware_revision = nsrt.read_fw_rev()
date_of_birth = nsrt.read_dob().replace(" ", "T")
date_of_calibration = nsrt.read_doc().replace(" ", "T")

#######################################
# Ensure sound weighting configured on device

weighting = nsrt.read_weighting()
if weighting != WEIGHTING:
    print("SETTING WEIGHTING TO " + WEIGHTING)
    nsrt.write_weighting(WEIGHTING)
    weighting = nsrt.read_weighting()
    assert weighting == WEIGHTING, "unable to set weighting to " + WEIGHTING
if weighting == WEIGHTING:  # Convert to printable string
    weighting = "dBC"

#######################################
# Gather Metadata and CSV columm header

tags = [
    "# measurement_name = decibels",
    f"# model = {model}",
    f"# serial = {serial_number}",
    f"# firmware = {firmware_revision}",
    f"# date_manufacture = {date_of_birth}",
    f"# date_calibration = {date_of_calibration}",
    f"# weighting = {weighting}",
]
columns = ["timestamp", "leq_level", "weighted_level"]
header = "\n".join(tags) + "\n" + ",".join(columns)

#######################################
# Setup the rotating CSV logs that will contain the metrics

# Ensure the log directory exists
os.makedirs(LOGDIR, mode=0o775, exist_ok=True)


# Custom Log File Rotator
#   Creates a custom header composed of InfluxDB metadata and CSV column names
class MyTimedRotatingFileHandler(TimedRotatingFileHandler):
    def __init__(
        self,
        filename,
        when="h",
        interval=1,
        backupCount=0,
        encoding=None,
        delay=False,
        utc=False,
        atTime=None,
        errors=None,
        header="",
    ):
        self.header = header
        super().__init__(
            filename,
            when,
            interval,
            backupCount,
            encoding,
            delay,
            utc,
            atTime,
            errors,
        )

    def _open(self):
        stream = super()._open()
        if self.header and stream.tell() == 0:
            stream.write(self.header + self.terminator)
            stream.flush()
        return stream


# Silence an asyncio log message
logging.getLogger("asyncio").setLevel(logging.WARNING)

# Configure logging
logging.basicConfig(
    level=logging.DEBUG, format="%(message)s", datefmt="%Y-%m-%dT%H:%M:%S%z"
)
logger = logging.getLogger(__name__)

# Create a logging handler
#   Change to 'm' for minute when debugging
handler = MyTimedRotatingFileHandler(
    LOGDIR + "/" + LOGFILENAME, when="midnight", header=header
)
handler.suffix = "%Y%m%d"
handler.extMatch = re.compile(r"^\d{8}$")
logger.addHandler(handler)

#######################################
# Run the work loop

tz = pytz.timezone(TIMEZONE)

while True:
    localized_date = tz.localize(datetime.now()).replace(microsecond=0)
    iso_date = localized_date.isoformat()
    leq_level = nsrt.read_leq()
    weighted_level = nsrt.read_level()
    logger.info(f"{iso_date},{leq_level:0.2f},{weighted_level:0.2f}")
    time.sleep(1)
