package com.stratio.spark.perfomance.testing

import org.apache.spark.sql.SQLContext
import org.apache.spark.{SparkConf, SparkContext}

object SinfoTestingMain {

  def main(args: Array[String]): Unit = {
    require(args.size == 2 || args.size == 4, "Please provide inputPath, OutputPath and optinionaly principal and " +
      "keytabPath")
    val conf = new SparkConf()
    val Array(input, output) = args
    val sc = new SparkContext(conf)
    val sqlContext = new SQLContext(sc)
    sqlContext.read.format("parquet").option("path", input).load.rdd.saveAsTextFile(output+System.currentTimeMillis)
  }
}
