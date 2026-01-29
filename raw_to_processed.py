import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame
from pyspark.sql.functions import col, when

# --- Init ---
args = getResolvedOptions(sys.argv, ['JOB_NAME'])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# --- Read from Data Catalog ---
raw_dyf = glueContext.create_dynamic_frame.from_catalog(
    database="reviews_raw_db",
    table_name="raw_raw",  # table_prefix + folder name
    transformation_ctx="raw_dyf"
)

# --- Select Fields ---
selected_dyf = SelectFields.apply(
    frame=raw_dyf,
    paths=["review_text", "rating", "recommended_ind", "division_name", 
           "department_name", "class_name", "review_id"],
    transformation_ctx="selected_dyf"
)

# --- Filter nulls ---
filtered_dyf = Filter.apply(
    frame=selected_dyf,
    f=lambda row: row["review_text"] is not None and row["rating"] is not None,
    transformation_ctx="filtered_dyf"
)

# --- Convert to DataFrame for sentiment column ---
df = filtered_dyf.toDF()

# --- Add sentiment column using PySpark when function ---
df = df.withColumn(
    "sentiment",
    when(col("rating") >= 4, "POSITIVE")
    .when(col("rating") == 3, "NEUTRAL")
    .otherwise("NEGATIVE")
)

# --- Convert back to DynamicFrame ---
final_dyf = DynamicFrame.fromDF(df, glueContext, "final_dyf")

# --- Write to S3 ---
glueContext.write_dynamic_frame.from_options(
    frame=final_dyf,
    connection_type="s3",
    format="csv",
    connection_options={
        "path": "s3://final-bucket-s3-reviews-data/final/",
    "partitionKeys": []
    },
    format_options={
        "withHeader": True
    },
    transformation_ctx="write_processed"
)

job.commit()
