// Behavioral tests for the durable-agent-pipeline module.
//
// TestExampleValidates      - always runs; no AWS credentials needed.
// TestDurableLifecycle      - runs when TERRATEST_APPLY=1; deploys the module
//
//	with the fixtures in test/fixtures, then proves the durable lifecycle:
//	start -> checkpointed step -> suspend -> external callback -> replay ->
//	result written. This is the behavior the module exists to guarantee;
//	"resources created" alone proves none of it.
//
// Before the lifecycle test, build the fixture packages:
//
//	./fixtures/build.sh
package test

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	ddbtypes "github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/aws/aws-sdk-go-v2/service/lambda"
	lambdatypes "github.com/aws/aws-sdk-go-v2/service/lambda/types"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
)

func TestExampleValidates(t *testing.T) {
	t.Parallel()

	// The example expects pre-built packages; stubs are enough to validate.
	for _, dir := range []string{"../examples/complete/build/orchestrator", "../examples/complete/build/api"} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(dir+"/lambda_function.py", []byte("# stub\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	opts := &terraform.Options{TerraformDir: "../examples/complete"}
	terraform.InitAndValidate(t, opts)
}

func TestDurableLifecycle(t *testing.T) {
	if os.Getenv("TERRATEST_APPLY") != "1" {
		t.Skip("set TERRATEST_APPLY=1 (with AWS credentials) to run the live behavioral test")
	}

	region := os.Getenv("AWS_REGION")
	if region == "" {
		region = "us-east-1"
	}
	runID := strings.ToLower(random.UniqueId())
	projectName := "dap-test-" + runID

	opts := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "fixtures/live",
		Vars: map[string]interface{}{
			"project_name": projectName,
			"aws_region":   region,
		},
	})
	defer terraform.Destroy(t, opts)
	terraform.InitAndApply(t, opts)

	orchestratorArn := terraform.Output(t, opts, "orchestrator_qualified_arn")
	tableName := terraform.Output(t, opts, "executions_table")
	bucket := terraform.Output(t, opts, "posts_bucket")

	ctx := context.Background()
	cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion(region))
	if err != nil {
		t.Fatal(err)
	}
	lambdaClient := lambda.NewFromConfig(cfg)
	ddbClient := dynamodb.NewFromConfig(cfg)
	s3Client := s3.NewFromConfig(cfg)

	// 1. Start: async-invoke through the qualified alias ARN (Rule 1).
	payload, _ := json.Marshal(map[string]string{"run_id": runID})
	_, err = lambdaClient.Invoke(ctx, &lambda.InvokeInput{
		FunctionName:   aws.String(orchestratorArn),
		InvocationType: lambdatypes.InvocationTypeEvent,
		Payload:        payload,
	})
	if err != nil {
		t.Fatalf("invoke via qualified ARN failed: %v", err)
	}

	// 2. Suspend: the fixture stores its callback ID once it has checkpointed
	//    a step and suspended (Rules 2+3).
	callbackID := pollForCallbackID(t, ctx, ddbClient, tableName, runID, 2*time.Minute)

	// 3. External callback: deliver approval from outside the function.
	echo := fmt.Sprintf(`{"approved": true, "run": %q}`, runID)
	_, err = lambdaClient.SendDurableExecutionCallbackSuccess(ctx, &lambda.SendDurableExecutionCallbackSuccessInput{
		CallbackId: aws.String(callbackID),
		Result:     []byte(echo),
	})
	if err != nil {
		t.Fatalf("SendDurableExecutionCallbackSuccess failed (check the versioned-ARN wildcard grant): %v", err)
	}

	// 4. Resume + result: the replayed execution writes to S3.
	body := pollForS3Object(t, ctx, s3Client, bucket, runID+".json", 2*time.Minute)

	var result struct {
		Marker string `json:"marker"`
		Echo   struct {
			Approved bool `json:"approved"`
		} `json:"echo"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		t.Fatalf("result unmarshal: %v (body: %s)", err, body)
	}
	if want := "step-completed-" + runID; result.Marker != want {
		t.Errorf("checkpointed step result: got %q, want %q", result.Marker, want)
	}
	if !result.Echo.Approved {
		t.Error("callback payload was not delivered through the resume")
	}
}

func pollForCallbackID(t *testing.T, ctx context.Context, client *dynamodb.Client, table, runID string, timeout time.Duration) string {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		out, err := client.GetItem(ctx, &dynamodb.GetItemInput{
			TableName: aws.String(table),
			Key:       map[string]ddbtypes.AttributeValue{"execution_id": &ddbtypes.AttributeValueMemberS{Value: runID}},
		})
		if err == nil && out.Item != nil {
			if v, ok := out.Item["callback_id"].(*ddbtypes.AttributeValueMemberS); ok {
				return v.Value
			}
		}
		time.Sleep(5 * time.Second)
	}
	t.Fatal("timed out waiting for the suspended execution to store its callback ID")
	return ""
}

func pollForS3Object(t *testing.T, ctx context.Context, client *s3.Client, bucket, key string, timeout time.Duration) []byte {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		out, err := client.GetObject(ctx, &s3.GetObjectInput{Bucket: aws.String(bucket), Key: aws.String(key)})
		if err == nil {
			defer out.Body.Close()
			buf := make([]byte, 65536)
			n, _ := out.Body.Read(buf)
			return buf[:n]
		}
		time.Sleep(5 * time.Second)
	}
	t.Fatal("timed out waiting for the resumed execution to write its result to S3")
	return nil
}
