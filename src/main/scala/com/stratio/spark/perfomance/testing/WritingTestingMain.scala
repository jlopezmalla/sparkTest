package com.stratio.spark.perfomance.testing

import java.nio.file.{Files, Paths}
import javax.xml.bind.DatatypeConverter

import org.apache.spark.sql.{DataFrame, SQLContext}
import org.apache.spark.{SparkConf, SparkContext}

object WritingTestingMain {

  def main(args: Array[String]): Unit = {
    require(args.size == 3 || args.size == 5, "Please provide inputPath, OutputPath, sparkSQLinputFormat and optinionaly principal and " +
      "keytabPath")
    val conf = new SparkConf()
    val Array(input, output, format) = args
    val sc = new SparkContext(conf)
    val sqlContext = new SQLContext(sc)
    val cache: DataFrame = sqlContext.read.format(format).option("path", input).load.cache
    cache.foreach(line => Nil)
    cache.rdd.saveAsTextFile(output + System.currentTimeMillis)
  }
}
