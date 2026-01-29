import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from awsglue.dynamicframe import DynamicFrame
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import col, when, trim, lower

args = getResolvedOptions(sys.argv, ['JOB_NAME'])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Read from raw database
datasource0 = glueContext.create_dynamic_frame.from_catalog(
    database = "reviews_raw_db",
    table_name = "raw_raw",
    transformation_ctx = "datasource0"
)

# Rename columns using ApplyMapping
applymapping1 = ApplyMapping.apply(
    frame = datasource0,
    mappings = [
        ("col0", "long", "review_id", "long"),
        ("col1", "string", "clothing_id", "string"),
        ("col2", "string", "age", "string"),
        ("col3", "string", "title", "string"),
        ("col4", "string", "review_text", "string"),
        ("col5", "string", "rating", "string"),
        ("col6", "string", "recommended_ind", "string"),
        ("col7", "string", "positive_feedback_count", "string"),
        ("col8", "string", "division_name", "string"),
        ("col9", "string", "department_name", "string"),
        ("col10", "string", "class_name", "string")
    ],
    transformation_ctx = "applymapping1"
)

# Convert to DataFrame for transformations
df = applymapping1.toDF()

# Apply transformations: clean nulls, cast types, convert boolean
df_transformed = df.filter(
    (col("rating").isNotNull()) & 
    (col("review_text").isNotNull()) &
    (trim(col("review_text")) != "")
).withColumn(
    "rating",
    col("rating").cast("integer")
).withColumn(
    "age",
    col("age").cast("integer")
).withColumn(
    "positive_feedback_count",
    col("positive_feedback_count").cast("integer")
).withColumn(
    "recommended_ind",
    when(lower(trim(col("recommended_ind"))) == "true", 1)
    .when(lower(trim(col("recommended_ind"))) == "false", 0)
    .otherwise(None)
)

# Convert back to DynamicFrame
dynamic_frame_final = DynamicFrame.fromDF(df_transformed, glueContext, "dynamic_frame_final")

# Write to processed bucket
datasink2 = glueContext.write_dynamic_frame.from_options(
    frame = dynamic_frame_final,
    connection_type = "s3",
    connection_options = {"path": "s3://processed-bucket-s3-reviews-data-ah/processed/"},
    format = "parquet",
    transformation_ctx = "datasink2"
)

job.commit()
