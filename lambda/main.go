package main

import (
	"context"
	"database/sql"
	"fmt"
	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	_ "github.com/marcboeker/go-duckdb"
	"os"
)

var db *sql.DB

func handler(ctx context.Context, event events.S3ObjectLambdaEvent) error {
	url := event.GetObjectContext.InputS3URL

	//if header is empty return first 10 rows of a table
	header := event.UserRequest.Headers["x-amz-meta-request-sql"] // should be like SELECT max(trip_distance) as max_distances FROM read_parquet('%s')
	if header == "" {
		header = "SELECT * FROM read_parquet('%s') LIMIT 10"
	}
	//fmt.Println("header: ", header)
	sqlQuery := fmt.Sprintf(header, url)

	// run a query and save result to ephemeral storage of lambda
	sqlCmd := fmt.Sprintf("COPY (%s) TO '/tmp/res.csv';", sqlQuery)
	//fmt.Println("SQL command: ", sqlCmd)

	check(db.ExecContext(context.Background(), sqlCmd))

	f, err := os.Open("/tmp/res.csv")
	check(err)
	defer f.Close()

	cfg, err := config.LoadDefaultConfig(context.TODO())
	check(err)

	svc := s3.NewFromConfig(cfg)
	input := &s3.WriteGetObjectResponseInput{
		RequestRoute: &event.GetObjectContext.OutputRoute,
		RequestToken: &event.GetObjectContext.OutputToken,
		Body:         f,
	}

	_, err = svc.WriteGetObjectResponse(ctx, input)
	check(err)

	err = os.Remove("/tmp/res.csv")
	check(err)

	return nil
}

func main() {
	var err error

	db, err = sql.Open("duckdb", "?access_mode=READ_WRITE")
	check(err)
	defer db.Close()
	check(db.Ping())

	check(db.ExecContext(context.Background(), "INSTALL httpfs;"))
	// load the installed extension. another option is to install an extension ^^^
	//check(db.ExecContext(context.Background(), "SET extension_directory = 'DuckDBExtensions';")) // DuckDBExtensions/v1.0.0/linux_arm64/httpfs.duckdb_extension
	check(db.ExecContext(context.Background(), "LOAD httpfs;"))

	lambda.Start(handler)
}

func check(args ...interface{}) {
	err := args[len(args)-1]
	if err != nil {
		panic(err)
	}
}
