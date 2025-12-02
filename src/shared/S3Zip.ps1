<#
Build-S3SinkWithGlue-NoUpload-Fixed.ps1
Creates a ZIP containing an S3 Sink connector + Parquet + AWS Glue Schema Registry jars
for use as an MSK Connect custom plugin.

- This script does NOT upload to S3.
- Recommended: run with Maven (default if mvn exists).
- Fallback: direct-download mode (may miss transitive dependencies).

Usage:
    .\Build-S3SinkWithGlue-NoUpload-Fixed.ps1
    .\Build-S3SinkWithGlue-NoUpload-Fixed.ps1 -UseMaven:$false

#>

param(
    [switch]$UseMaven,         # pass -UseMaven:$true or -UseMaven:$false; if omitted the script auto-selects based on presence of mvn
    [string]$WorkRoot = (Join-Path (Get-Location) "s3-sink-plugin-builder")
)

# -------- CONFIGURE VERSIONS (edit if needed) --------
$S3_CONNECTOR_GROUP     = "io.aiven"
$S3_CONNECTOR_ARTIFACT  = "s3-connector-for-apache-kafka"
$S3_CONNECTOR_VERSION   = "2.15.0"

$PARQUET_GROUP          = "org.apache.parquet"
$PARQUET_ARTIFACT       = "parquet-avro"
$PARQUET_VERSION        = "1.15.1"

$GLUE_CONVERTER_GROUP   = "software.amazon.glue"
$GLUE_CONVERTER_ARTIFACT= "schema-registry-kafkaconnect-converter"
$GLUE_SERDE_GROUP       = "software.amazon.glue"
$GLUE_SERDE_ARTIFACT    = "schema-registry-serde"
$GLUE_SR_VERSION        = "1.1.25"

$PLUGIN_NAME            = "s3-sink-with-glue"
$WORKDIR                = $WorkRoot
$LIBDIR                 = Join-Path $WORKDIR "lib"
$PLUGIN_DIR             = Join-Path $WORKDIR $PLUGIN_NAME
$OUT_ZIP                = Join-Path (Get-Location) "$PLUGIN_NAME-$($S3_CONNECTOR_VERSION)-parquet-glue-$($GLUE_SR_VERSION).zip"

# Auto-select UseMaven if not explicitly provided
if (-not $PSBoundParameters.ContainsKey('UseMaven')) {
    if (Get-Command mvn -ErrorAction SilentlyContinue) {
        $UseMaven = $true
    } else {
        $UseMaven = $false
    }
}

Write-Host "UseMaven = $UseMaven"
Write-Host "Workspace: $WORKDIR"

# -------- Prepare workspace --------
if (Test-Path $WORKDIR) {
    Write-Host "Cleaning existing workspace at $WORKDIR"
    Remove-Item -Recurse -Force $WORKDIR
}
New-Item -ItemType Directory -Path $WORKDIR | Out-Null
New-Item -ItemType Directory -Path $LIBDIR | Out-Null

function GroupToPath($group) {
    return ($group -split '\.') -join '/'
}

# -------- Mode A: Use Maven to copy runtime deps (recommended) --------
if ($UseMaven) {
    if (-not (Get-Command mvn -ErrorAction SilentlyContinue)) {
        Write-Error "Maven (mvn) not found in PATH. Install Maven or run with -UseMaven:$false for direct-download fallback."
        exit 1
    }

    # Build pom.xml with additional repositories (Confluent etc.)
    $pom = @"
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
                             https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>local.s3.plugin</groupId>
  <artifactId>s3-sink-plugin-builder</artifactId>
  <version>1.0.0</version>

  <repositories>
    <!-- Confluent repository for confluent artifacts -->
    <repository>
      <id>confluent</id>
      <url>https://packages.confluent.io/maven/</url>
      <releases><enabled>true</enabled></releases>
      <snapshots><enabled>false</enabled></snapshots>
    </repository>

    <!-- Maven Central -->
    <repository>
      <id>central</id>
      <url>https://repo.maven.apache.org/maven2</url>
      <releases><enabled>true</enabled></releases>
      <snapshots><enabled>false</enabled></snapshots>
    </repository>

    <!-- Apache releases -->
    <repository>
      <id>apache-releases</id>
      <url>https://repository.apache.org/content/repositories/releases/</url>
      <releases><enabled>true</enabled></releases>
      <snapshots><enabled>false</enabled></snapshots>
    </repository>
  </repositories>

  <dependencies>
    <!-- S3 Sink connector (Aiven) -->
    <dependency>
      <groupId>$S3_CONNECTOR_GROUP</groupId>
      <artifactId>$S3_CONNECTOR_ARTIFACT</artifactId>
      <version>$S3_CONNECTOR_VERSION</version>
    </dependency>

    <!-- Parquet Avro -->
    <dependency>
      <groupId>$PARQUET_GROUP</groupId>
      <artifactId>$PARQUET_ARTIFACT</artifactId>
      <version>$PARQUET_VERSION</version>
    </dependency>

    <!-- AWS Glue Schema Registry converter + serde -->
    <dependency>
      <groupId>$GLUE_CONVERTER_GROUP</groupId>
      <artifactId>$GLUE_CONVERTER_ARTIFACT</artifactId>
      <version>$GLUE_SR_VERSION</version>
    </dependency>

    <dependency>
      <groupId>$GLUE_SERDE_GROUP</groupId>
      <artifactId>$GLUE_SERDE_ARTIFACT</artifactId>
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
    $pom | Out-File -FilePath $pomPath -Encoding UTF8
    Write-Host "Created pom.xml at $pomPath"

    Write-Host "Running: mvn dependency:copy-dependencies ..."
    Push-Location $WORKDIR
    $mvnArgs = "dependency:copy-dependencies -DoutputDirectory=lib -DincludeScope=runtime -DexcludeTypes=pom"
    $proc = Start-Process mvn -ArgumentList $mvnArgs -NoNewWindow -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Write-Error "Maven failed (exit code $($proc.ExitCode)). Check Maven output in $WORKDIR. Exiting."
        Pop-Location
        exit 1
    }
    Pop-Location
    Write-Host "Dependencies copied into $LIBDIR (including transitive runtime deps)."
}
else {
    # -------- Mode B: Direct download main jars from Maven Central (fallback) --------
    Write-Host "Using direct-download fallback mode (may miss transitive dependencies)."

    $baseRepo = "https://repo1.maven.org/maven2"

    $artifacts = @(
        @{ group = $S3_CONNECTOR_GROUP; artifact = $S3_CONNECTOR_ARTIFACT; version = $S3_CONNECTOR_VERSION },
        @{ group = $PARQUET_GROUP; artifact = $PARQUET_ARTIFACT; version = $PARQUET_VERSION },
        @{ group = $GLUE_CONVERTER_GROUP; artifact = $GLUE_CONVERTER_ARTIFACT; version = $GLUE_SR_VERSION },
        @{ group = $GLUE_SERDE_GROUP; artifact = $GLUE_SERDE_ARTIFACT; version = $GLUE_SR_VERSION }
    )

    foreach ($a in $artifacts) {
        $gpath = GroupToPath $a.group
        $jarName = "$($a.artifact)-$($a.version).jar"
        $url = "$baseRepo/$gpath/$($a.artifact)/$($a.version)/$jarName"
        $dest = Join-Path $LIBDIR $jarName
        Write-Host "Downloading: $url"
        try {
            Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -ErrorAction Stop
            Write-Host "Saved -> $dest"
        } catch {
            Write-Warning "Failed to download $url : $($_.Exception.Message)"
        }
    }

    Write-Warning "Direct-download mode only fetches the primary artifact JARs. Many connectors require transitive dependencies at runtime. If connector fails at startup, install Maven and re-run the script with -UseMaven to fetch transitive dependencies."
}

# -------- Create plugin directory structure and copy jars --------
if (Test-Path $PLUGIN_DIR) { Remove-Item -Recurse -Force $PLUGIN_DIR }
New-Item -ItemType Directory -Path $PLUGIN_DIR | Out-Null

# Copy jars into plugin root
Get-ChildItem -Path $LIBDIR -Filter "*.jar" | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination $PLUGIN_DIR
}

# -------- Create README with safe interpolation --------
$modeText = $(if ($UseMaven) { 'Maven' } else { 'Direct-download' })
$readme = @"
S3 Sink Connector plugin with Parquet + AWS Glue Schema Registry jars
- Connector: ${S3_CONNECTOR_GROUP}:${S3_CONNECTOR_ARTIFACT}:${S3_CONNECTOR_VERSION}
- Parquet: ${PARQUET_GROUP}:${PARQUET_ARTIFACT}:${PARQUET_VERSION}
- Glue SR: ${GLUE_CONVERTER_GROUP}:${GLUE_CONVERTER_ARTIFACT}:${GLUE_SR_VERSION} and ${GLUE_SERDE_GROUP}:${GLUE_SERDE_ARTIFACT}:${GLUE_SR_VERSION}

Mode used: $modeText
"@

$readmePath = Join-Path $PLUGIN_DIR "README.txt"
$readme | Out-File -FilePath $readmePath -Encoding UTF8
Write-Host "Wrote README -> $readmePath"

# -------- Create ZIP file for MSK Connect custom plugin --------
if (Test-Path $OUT_ZIP) { Remove-Item $OUT_ZIP -Force }
Write-Host "Creating plugin ZIP: $OUT_ZIP"
Add-Type -AssemblyName 'System.IO.Compression.FileSystem'
[System.IO.Compression.ZipFile]::CreateFromDirectory($PLUGIN_DIR, $OUT_ZIP)

Write-Host "Plugin ZIP created: $OUT_ZIP"
Write-Host ""
Write-Host "Next steps:"
Write-Host " 1) Upload the ZIP to an S3 bucket (manually) and register it as an MSK Connect custom plugin."
Write-Host " 2) When creating your MSK Connect connector, configure converters like:"
Write-Host "    key.converter=software.amazon.glue.kafkaconnect.AWSKafkaAvroConverter"
Write-Host "    value.converter=software.amazon.glue.kafkaconnect.AWSKafkaAvroConverter"
Write-Host "    value.converter.glue.schema.registry.region=<region>"
Write-Host "    value.converter.schema.auto.registration.enabled=true"
Write-Host ""
Write-Host "Important note: If you used direct-download mode, the ZIP may be missing transitive dependencies and the connector might fail to start. Use Maven mode for a complete plugin ZIP."
