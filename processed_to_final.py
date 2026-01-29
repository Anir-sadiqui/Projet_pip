import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job

args = getResolvedOptions(sys.argv, ['JOB_NAME'])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Read from processed database (already cleaned data)
datasource0 = glueContext.create_dynamic_frame.from_catalog(
    database = "reviews_processed_db",
    table_name = "processed_processed",
    transformation_ctx = "datasource0"
)

# Write to final bucket (just copy the clean data)
datasink2 = glueContext.write_dynamic_frame.from_options(
    frame = datasource0,
    connection_type = "s3",
    connection_options = {"path": "s3://final-bucket-s3-reviews-data-ah/final/"},
    format = "parquet",
    transformation_ctx = "datasink2"
)

job.commit()
