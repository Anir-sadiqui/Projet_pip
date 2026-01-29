import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame
from pyspark.sql.functions import upper, lower

# --- Init Glue ---
args = getResolvedOptions(sys.argv, ['JOB_NAME'])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# --- Read from Data Catalog (PROCESSED) ---
processed_dyf = glueContext.create_dynamic_frame.from_catalog(
    database="reviews_processed_db",
    table_name="processed_processed",  # table_prefix + folder name
    transformation_ctx="processed_dyf"
)

# --- Select final columns ---
selected_dyf = SelectFields.apply(
    frame=processed_dyf,
    paths=[
        "review_id",
        "review_text",
        "rating",
        "sentiment",
        "department_name"
    ],
    transformation_ctx="selected_dyf"
)

# --- Convert to DataFrame for normalization ---
df = selected_dyf.toDF()

# --- Normalize text fields ---
df = df.withColumn("sentiment", upper(col("sentiment"))) \
       .withColumn("department_name", lower(col("department_name")))

# --- Convert back to DynamicFrame ---
final_dyf = DynamicFrame.fromDF(df, glueContext, "final_dyf")

# --- Write to S3 FINAL (Parquet) ---
glueContext.write_dynamic_frame.from_options(
    frame=final_dyf,
    connection_type="s3",
    format="parquet",
    connection_options={
        "path": "s3://review-csv-final-data/final/",
        "partitionKeys": []
    },
    transformation_ctx="write_final"
)

job.commit()
