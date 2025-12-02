<#
PowerShell script: build-debezium-postgres-with-glue.ps1
Creates a ZIP containing Debezium Postgres connector + AWS Glue Schema Registry jars
for use as an MSK Connect custom plugin.

Usage:
  1. Edit versions below if you want different releases.
  2. Run in PowerShell (requires mvn on PATH).
  3. Upload the resulting ZIP to an S3 bucket and register as an MSK Connect custom plugin.

Notes:
  - This script creates a temporary Maven project in the working directory.
  - It uses 'mvn dependency:copy-dependencies' to pull the connector + runtime deps.
#>

# -------- CONFIGURE VERSIONS (edit if needed) --------
$DEBEZIUM_VERSION = "3.3.2.Final"        # Debezium Postgres connector version (change if you prefer)
$GLUE_SR_VERSION   = "1.1.25"            # AWS Glue Schema Registry library version (converter + serde)
$PLUGIN_NAME       = "debezium-postgres-with-glue"
$WORKDIR           = Join-Path -Path (Get-Location) -ChildPath "debezium-plugin-builder"
$LIBDIR            = Join-Path $WORKDIR "lib"
$PLUGIN_DIR        = Join-Path $WORKDIR "$PLUGIN_NAME"
$OUT_ZIP           = Join-Path (Get-Location) "$PLUGIN_NAME-$($DEBEZIUM_VERSION)-glue-$($GLUE_SR_VERSION).zip"

# -------- Prereq check: mvn and java --------
Write-Host "Checking prerequisites..."
if (-not (Get-Command mvn -ErrorAction SilentlyContinue)) {
    Write-Error "Maven (mvn) not found in PATH. Install Maven and re-run. Exiting."
    exit 1
}
if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
    Write-Error "Java not found in PATH. Install JDK and re-run. Exiting."
    exit 1
}

# -------- Clean and prepare workspace --------
if (Test-Path $WORKDIR) {
    Write-Host "Cleaning existing workspace at $WORKDIR"
    Remove-Item -Recurse -Force $WORKDIR
}
New-Item -ItemType Directory -Path $WORKDIR | Out-Null
New-Item -ItemType Directory -Path $LIBDIR | Out-Null

# -------- Write a minimal pom.xml with required dependencies --------
$pom = @"
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
                             https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>local.debezium.plugin</groupId>
  <artifactId>debezium-plugin-builder</artifactId>
  <version>1.0.0</version>
  <packaging>jar</packaging>

  <dependencies>
    <!-- Debezium Postgres connector (pulls core + deps transitively) -->
    <dependency>
      <groupId>io.debezium</groupId>
      <artifactId>debezium-connector-postgres</artifactId>
      <version>$DEBEZIUM_VERSION</version>
    </dependency>

    <!-- AWS Glue Schema Registry Kafka Connect converter -->
    <dependency>
      <groupId>software.amazon.glue</groupId>
      <artifactId>schema-registry-kafkaconnect-converter</artifactId>
      <version>$GLUE_SR_VERSION</version>
    </dependency>

    <!-- AWS Glue Schema Registry serde (serializer/deserializer) -->
    <dependency>
      <groupId>software.amazon.glue</groupId>
      <artifactId>schema-registry-serde</artifactId>
      <version>$GLUE_SR_VERSION</version>
    </dependency>
  </dependencies>

  <build>
    <plugins>
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-dependency-plugin</artifactId>
        <version>3.5.0</version>
      </plugin>
    </plugins>
  </build>
</project>
"@

$pomPath = Join-Path $WORKDIR "pom.xml"
$pom | Out-File -FilePath $pomPath -Encoding utf8

Write-Host "Created pom.xml at $pomPath"

# -------- Use Maven to copy runtime dependencies into lib/ --------
Write-Host "Downloading connector and dependencies via Maven..."
Push-Location $WORKDIR
$mvnArgs = "dependency:copy-dependencies -DoutputDirectory=lib -DincludeScope=runtime -DexcludeTypes=pom"
$proc = Start-Process mvn -ArgumentList $mvnArgs -NoNewWindow -Wait -PassThru
if ($proc.ExitCode -ne 0) {
    Write-Error "Maven failed (exit code $($proc.ExitCode)). Check Maven output. Exiting."
    Pop-Location
    exit 1
}
Pop-Location
Write-Host "Dependencies copied into $LIBDIR"

# -------- Create plugin directory structure and copy jars --------
if (Test-Path $PLUGIN_DIR) { Remove-Item -Recurse -Force $PLUGIN_DIR }
New-Item -ItemType Directory -Path $PLUGIN_DIR | Out-Null

# Copy all jars from lib to the plugin root (MSK Connect accepts a ZIP with JARs).
Get-ChildItem -Path $LIBDIR -Filter "*.jar" | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination $PLUGIN_DIR
}

# Also copy *any* connector-specific resources we might want (optional)
# (e.g., README or connector plugin descriptor if you have one)
# You can add plugin-specific files here if needed.

# -------- Create ZIP file for MSK Connect custom plugin --------
if (Test-Path $OUT_ZIP) { Remove-Item $OUT_ZIP -Force }
Write-Host "Creating plugin ZIP: $OUT_ZIP"
Add-Type -AssemblyName 'System.IO.Compression.FileSystem'
[System.IO.Compression.ZipFile]::CreateFromDirectory($PLUGIN_DIR, $OUT_ZIP)

Write-Host "Plugin ZIP created: $OUT_ZIP"
Write-Host ""
Write-Host "Next steps:"
Write-Host " 1) Upload the ZIP to an S3 bucket (aws s3 cp $OUT_ZIP s3://your-bucket/) and register it as an MSK Connect custom plugin."
Write-Host " 2) When creating an MSK Connect worker/connector, use the plugin and configure converters to use the AWS Glue converters."
Write-Host ""
Write-Host "Example connector converter config (for reference):"
Write-Host "  key.converter=software.amazon.glue.kafkaconnect.AWSKafkaAvroConverter"
Write-Host "  value.converter=software.amazon.glue.kafkaconnect.AWSKafkaAvroConverter"
Write-Host "  key.converter.glue.schema.registry.region=us-east-1"
Write-Host "  value.converter.glue.schema.registry.region=us-east-1"
Write-Host ""
Write-Host "Script finished."
