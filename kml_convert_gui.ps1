Set-StrictMode -Version Latest

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:kmlConvertGuiConfig = @{
	cliScriptName = 'scale-kml.js'
	defaultTargetObjectName = 'Mars'
	earthMeanRadiusKm = 6371
	mapAspectRatio = 2.0
	mapAspectRatioTolerance = 0.02
	fallbackMapWidth = 1200
	fallbackMapHeight = 600
	mapCatalogRelativePath = 'locations\map_images.json'
	digistar = @{
		templateDirectoryName = 'digistar_templates'
		addTemplateFileName = 'addKmlObjectToCustomPlanet.ds'
		removeTemplateFileName = 'removeKmlObjectToCustomPlanet.ds'
		methodName = 'greatCircle'
		reservedOptionsPart = 'default'
		maximumObjectNameLength = 49
		maximumPlanetCopyObjectLength = 34
		planetCopySuffix = 'Planet'
		kmlObjectSuffix = 'Kml'
		stableHashLength = 6
		placeholders = [ordered]@{
			convertedKmlPath = '{{convertedKmlPath}}'
			targetObject = '{{targetObject}}'
			planetCopyObjectName = '{{planetCopyObjectName}}'
			kmlObjectName = '{{kmlObjectName}}'
			radiusExpression = '{{radiusExpression}}'
		}
	}
	targetObjects = @(
		[pscustomobject]@{ key = 'sun'; name = 'Sun'; radiusKm = 696000 },
		[pscustomobject]@{ key = 'mercury'; name = 'Mercury'; radiusKm = 2439.4 },
		[pscustomobject]@{ key = 'venus'; name = 'Venus'; radiusKm = 6051.8 },
		[pscustomobject]@{ key = 'earth'; name = 'Earth'; radiusKm = 6371.0084 },
		[pscustomobject]@{ key = 'moon'; name = 'Moon'; radiusKm = 1737.4 },
		[pscustomobject]@{ key = 'mars'; name = 'Mars'; radiusKm = 3389.5 },
		[pscustomobject]@{ key = 'jupiter'; name = 'Jupiter'; radiusKm = 69911 },
		[pscustomobject]@{ key = 'saturn'; name = 'Saturn'; radiusKm = 58232 },
		[pscustomobject]@{ key = 'uranus'; name = 'Uranus'; radiusKm = 25362 },
		[pscustomobject]@{ key = 'neptune'; name = 'Neptune'; radiusKm = 24622 },
		[pscustomobject]@{ key = 'pluto'; name = 'Pluto'; radiusKm = 1188.3 }
	)
}

function Get-KmlConvertGuiCliScriptPath {
	$cliScriptPath = Join-Path $PSScriptRoot $script:kmlConvertGuiConfig.cliScriptName

	if (-not (Test-Path -LiteralPath $cliScriptPath -PathType Leaf)) {
		throw 'CLI script not found: ' + $cliScriptPath
	}

	return $cliScriptPath
}

function Get-KmlConvertGuiNodeCommand {
	$nodeCommand = Get-Command node -ErrorAction SilentlyContinue

	if (-not $nodeCommand) {
		throw 'node is not available on PATH. Install Node.js and reopen the GUI.'
	}

	return $nodeCommand.Source
}

function Get-KmlConvertGuiTargetObjectDefinitions {
	return $script:kmlConvertGuiConfig.targetObjects
}

function Get-KmlConvertGuiTargetObjectDefinition {
	param(
		[string]$TargetObjectName
	)

	$trimmedTargetObjectName = ''
	$index = 0
	$currentTargetObject = $null

	if ($null -ne $TargetObjectName) {
		$trimmedTargetObjectName = $TargetObjectName.Trim()
	}

	if ($trimmedTargetObjectName -eq '') {
		throw 'Target object is required.'
	}

	for ($index = 0; $index -lt $script:kmlConvertGuiConfig.targetObjects.Count; $index += 1) {
		$currentTargetObject = $script:kmlConvertGuiConfig.targetObjects[$index]

		if (
			$currentTargetObject.name.Equals($trimmedTargetObjectName, [System.StringComparison]::OrdinalIgnoreCase) -or
			$currentTargetObject.key.Equals($trimmedTargetObjectName, [System.StringComparison]::OrdinalIgnoreCase)
		) {
			return $currentTargetObject
		}
	}

	throw 'Unsupported target object: ' + $TargetObjectName
}

function Get-KmlConvertGuiMapCatalogPath {
	param(
		[string]$MapCatalogPath
	)

	if ($null -ne $MapCatalogPath -and $MapCatalogPath.Trim() -ne '') {
		return [System.IO.Path]::GetFullPath($MapCatalogPath)
	}

	return [System.IO.Path]::GetFullPath(
		(Join-Path $PSScriptRoot $script:kmlConvertGuiConfig.mapCatalogRelativePath)
	)
}

function Read-KmlConvertGuiMapCatalog {
	param(
		[string]$MapCatalogPath
	)

	$resolvedCatalogPath = Get-KmlConvertGuiMapCatalogPath -MapCatalogPath $MapCatalogPath
	$catalogDirectory = [System.IO.Path]::GetDirectoryName($resolvedCatalogPath)
	$catalogText = ''
	$catalogData = $null
	$mapProperties = $null
	$entries = [ordered]@{}
	$targetObject = $null
	$targetKeyPattern = ''
	$entryProperty = $null
	$entry = $null
	$fileName = ''
	$sourceDescription = ''
	$sourceUrl = ''
	$sourceUri = $null
	$attribution = ''
	$redistributionLicense = ''
	$redistributionAllowedProperty = $null
	$imagePath = ''
	$catalogDirectoryRoot = ''
	$pathParts = $null

	if (-not (Test-Path -LiteralPath $resolvedCatalogPath -PathType Leaf)) {
		throw 'Map image catalog not found: ' + $resolvedCatalogPath
	}

	try {
		$catalogText = [System.IO.File]::ReadAllText($resolvedCatalogPath)
		$catalogData = $catalogText | ConvertFrom-Json
	} catch {
		throw 'Map image catalog is malformed: ' + $resolvedCatalogPath
	}

	if ($null -eq $catalogData -or $null -eq $catalogData.PSObject.Properties['schemaVersion']) {
		throw 'Map image catalog must contain schemaVersion 1.'
	}

	if ($catalogData.schemaVersion -isnot [int] -or [int]$catalogData.schemaVersion -ne 1) {
		throw 'Unsupported map image catalog schemaVersion: ' + [string]$catalogData.schemaVersion
	}

	if (
		$null -eq $catalogData.PSObject.Properties['maps'] -or
		$null -eq $catalogData.maps -or
		$catalogData.maps -isnot [System.Management.Automation.PSCustomObject]
	) {
		throw 'Map image catalog must contain a maps object.'
	}

	$mapProperties = @($catalogData.maps.PSObject.Properties)

	foreach ($targetObject in $script:kmlConvertGuiConfig.targetObjects) {
		$targetKeyPattern = '(?<!\\)"' + [System.Text.RegularExpressions.Regex]::Escape([string]$targetObject.key) + '"\s*:'

		if (
			[System.Text.RegularExpressions.Regex]::Matches(
				$catalogText,
				$targetKeyPattern,
				[System.Text.RegularExpressions.RegexOptions]::IgnoreCase
			).Count -gt 1
		) {
			throw 'Duplicate map catalog entry for target key: ' + [string]$targetObject.key
		}
	}

	$catalogDirectoryRoot = [System.IO.Path]::GetFullPath($catalogDirectory).TrimEnd(
		[System.IO.Path]::DirectorySeparatorChar,
		[System.IO.Path]::AltDirectorySeparatorChar
	) + [System.IO.Path]::DirectorySeparatorChar

	foreach ($entryProperty in $mapProperties) {
		try {
			$targetObject = Get-KmlConvertGuiTargetObjectDefinition -TargetObjectName $entryProperty.Name
		} catch {
			throw 'Unknown map catalog target key: ' + $entryProperty.Name
		}

		if (-not $targetObject.key.Equals($entryProperty.Name, [System.StringComparison]::Ordinal)) {
			throw 'Map catalog target keys must use the exact lowercase target key: ' + $entryProperty.Name
		}

		$entry = $entryProperty.Value

		if (
			$null -eq $entry -or
			$entry -isnot [System.Management.Automation.PSCustomObject]
		) {
			throw 'Map catalog entry is unusable for target key: ' + $entryProperty.Name
		}

		foreach ($requiredPropertyName in @('fileName', 'sourceDescription', 'attribution', 'redistributionAllowed', 'redistributionLicense')) {
			if ($null -eq $entry.PSObject.Properties[$requiredPropertyName]) {
				throw 'Map catalog entry ' + $entryProperty.Name + ' is missing required field: ' + $requiredPropertyName
			}
		}

		foreach ($requiredTextPropertyName in @('fileName', 'sourceDescription', 'attribution', 'redistributionLicense')) {
			if ($entry.PSObject.Properties[$requiredTextPropertyName].Value -isnot [string]) {
				throw 'Map catalog field ' + $requiredTextPropertyName + ' must be a JSON string for target key: ' + $entryProperty.Name
			}
		}

		$fileName = [string]$entry.fileName
		$sourceDescription = [string]$entry.sourceDescription
		$attribution = [string]$entry.attribution
		$redistributionLicense = [string]$entry.redistributionLicense
		$redistributionAllowedProperty = $entry.PSObject.Properties['redistributionAllowed']

		if (
			$fileName.Trim() -eq '' -or
			$sourceDescription.Trim() -eq '' -or
			$attribution.Trim() -eq '' -or
			$redistributionLicense.Trim() -eq ''
		) {
			throw 'Map catalog entry contains a blank required field for target key: ' + $entryProperty.Name
		}

		if ($redistributionAllowedProperty.Value -isnot [bool]) {
			throw 'Map catalog redistributionAllowed must be a JSON boolean for target key: ' + $entryProperty.Name
		}

		$sourceUrl = ''

		if ($null -ne $entry.PSObject.Properties['sourceUrl'] -and $null -ne $entry.sourceUrl) {
			if ($entry.sourceUrl -isnot [string]) {
				throw 'Map catalog sourceUrl must be a JSON string or null for target key: ' + $entryProperty.Name
			}

			$sourceUrl = [string]$entry.sourceUrl
			$sourceUri = $null

			if (
				$sourceUrl.Trim() -ne '' -and
				-not (
					[System.Uri]::TryCreate($sourceUrl, [System.UriKind]::Absolute, [ref]$sourceUri) -and
					(
						$sourceUri.Scheme.Equals('http', [System.StringComparison]::OrdinalIgnoreCase) -or
						$sourceUri.Scheme.Equals('https', [System.StringComparison]::OrdinalIgnoreCase)
					)
				)
			) {
				throw 'Map catalog sourceUrl must use http or https for target key: ' + $entryProperty.Name
			}
		}

		if (
			[System.IO.Path]::IsPathRooted($fileName) -or
			$fileName -match '^[A-Za-z][A-Za-z0-9+.-]*:'
		) {
			throw 'Map catalog fileName must be a local relative path for target key: ' + $entryProperty.Name
		}

		$pathParts = $fileName -split '[\\/]'

		if ($pathParts -contains '..') {
			throw 'Map catalog fileName cannot contain path traversal for target key: ' + $entryProperty.Name
		}

		$imagePath = [System.IO.Path]::GetFullPath((Join-Path $catalogDirectory $fileName))

		if (-not $imagePath.StartsWith($catalogDirectoryRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
			throw 'Map catalog fileName must stay inside the catalog directory for target key: ' + $entryProperty.Name
		}

		$entries.Add(
			[string]$targetObject.key,
			[pscustomobject]@{
				TargetKey = [string]$targetObject.key
				FileName = $fileName
				ImagePath = $imagePath
				SourceDescription = $sourceDescription
				SourceUrl = $sourceUrl
				Attribution = $attribution
				RedistributionAllowed = [bool]$redistributionAllowedProperty.Value
				RedistributionLicense = $redistributionLicense
			}
		)
	}

	return [pscustomobject]@{
		CatalogPath = $resolvedCatalogPath
		CatalogDirectory = $catalogDirectory
		SchemaVersion = 1
		Entries = $entries
	}
}

function Get-KmlConvertGuiTargetMapCatalogEntry {
	param(
		[string]$TargetObjectName,
		[string]$MapCatalogPath
	)

	$targetObject = Get-KmlConvertGuiTargetObjectDefinition -TargetObjectName $TargetObjectName
	$catalog = Read-KmlConvertGuiMapCatalog -MapCatalogPath $MapCatalogPath

	if (-not $catalog.Entries.Contains([string]$targetObject.key)) {
		return $null
	}

	return $catalog.Entries[[string]$targetObject.key]
}

function Get-KmlConvertGuiTargetMapPath {
	param(
		[string]$TargetObjectName,
		[string]$MapCatalogPath
	)

	$entry = Get-KmlConvertGuiTargetMapCatalogEntry `
		-TargetObjectName $TargetObjectName `
		-MapCatalogPath $MapCatalogPath

	if ($null -eq $entry) {
		return $null
	}

	return $entry.ImagePath
}

function Test-KmlConvertGuiMapAspectRatio {
	param(
		[int]$Width,
		[int]$Height
	)

	if ($Width -le 0 -or $Height -le 0) {
		return $false
	}

	$aspectRatio = [double]$Width / [double]$Height
	return [Math]::Abs($aspectRatio - $script:kmlConvertGuiConfig.mapAspectRatio) -le $script:kmlConvertGuiConfig.mapAspectRatioTolerance
}

function New-KmlConvertGuiFallbackMapBitmap {
	$bitmap = New-Object System.Drawing.Bitmap(
		$script:kmlConvertGuiConfig.fallbackMapWidth,
		$script:kmlConvertGuiConfig.fallbackMapHeight,
		[System.Drawing.Imaging.PixelFormat]::Format24bppRgb
	)
	$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
	$gridPen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 1)
	$axisPen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 3)
	$index = 0
	$x = 0
	$y = 0

	try {
		$graphics.Clear([System.Drawing.Color]::Black)
		$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

		for ($index = 1; $index -lt 12; $index += 1) {
			$x = [single]($bitmap.Width * $index / 12)
			$graphics.DrawLine($gridPen, $x, 0, $x, $bitmap.Height)
		}

		for ($index = 1; $index -lt 6; $index += 1) {
			$y = [single]($bitmap.Height * $index / 6)
			$graphics.DrawLine($gridPen, 0, $y, $bitmap.Width, $y)
		}

		$graphics.DrawLine($axisPen, [single]($bitmap.Width / 2), 0, [single]($bitmap.Width / 2), $bitmap.Height)
		$graphics.DrawLine($axisPen, 0, [single]($bitmap.Height / 2), $bitmap.Width, [single]($bitmap.Height / 2))
	} finally {
		$axisPen.Dispose()
		$gridPen.Dispose()
		$graphics.Dispose()
	}

	return $bitmap
}

function Get-KmlConvertGuiTargetMapImage {
	param(
		[string]$TargetObjectName,
		[string]$MapCatalogPath
	)

	$targetObject = Get-KmlConvertGuiTargetObjectDefinition -TargetObjectName $TargetObjectName
	$mapEntry = $null
	$mapImagePath = $null
	$fallbackReason = ''
	$imageBytes = $null
	$imageStream = $null
	$decodedImage = $null
	$bitmap = $null

	try {
		$mapEntry = Get-KmlConvertGuiTargetMapCatalogEntry `
			-TargetObjectName $TargetObjectName `
			-MapCatalogPath $MapCatalogPath
	} catch {
		$fallbackReason = $_.Exception.Message
	}

	if ($null -ne $mapEntry) {
		$mapImagePath = $mapEntry.ImagePath
	}

	if ($fallbackReason -ne '') {
		$mapImagePath = $null
	} elseif ($null -eq $mapEntry) {
		$fallbackReason = 'No map image is registered for ' + $targetObject.name + '.'
	} elseif (-not (Test-Path -LiteralPath $mapImagePath -PathType Leaf)) {
		$fallbackReason = 'Registered map image not found: ' + $mapImagePath
	} else {
		try {
			$imageBytes = [System.IO.File]::ReadAllBytes($mapImagePath)
			$imageStream = New-Object System.IO.MemoryStream -ArgumentList (,$imageBytes)
			$decodedImage = [System.Drawing.Image]::FromStream($imageStream)

			if (-not (Test-KmlConvertGuiMapAspectRatio -Width $decodedImage.Width -Height $decodedImage.Height)) {
				$fallbackReason = 'Map image must be approximately 2:1: ' + $mapImagePath
			} else {
				$bitmap = New-Object System.Drawing.Bitmap -ArgumentList $decodedImage
			}
		} catch {
			$fallbackReason = 'Map image could not be decoded: ' + $mapImagePath
		} finally {
			if ($null -ne $decodedImage) {
				$decodedImage.Dispose()
			}

			if ($null -ne $imageStream) {
				$imageStream.Dispose()
			}
		}
	}

	if ($null -ne $bitmap) {
		$provenanceMessage = 'Source: ' + $mapEntry.SourceDescription + ' Attribution: ' + $mapEntry.Attribution + '.'

		if ($mapEntry.SourceUrl -ne '') {
			$provenanceMessage += ' Source URL: ' + $mapEntry.SourceUrl + '.'
		}

		if ($mapEntry.RedistributionAllowed) {
			$provenanceMessage += ' Redistribution license: ' + $mapEntry.RedistributionLicense + '.'
		} else {
			$provenanceMessage += ' Redistribution is not allowed: ' + $mapEntry.RedistributionLicense + '.'
		}

		return [pscustomobject]@{
			Bitmap = $bitmap
			IsFallback = $false
			TargetObjectName = [string]$targetObject.name
			MapImagePath = [System.IO.Path]::GetFullPath($mapImagePath)
			CatalogEntry = $mapEntry
			Message = $provenanceMessage
		}
	}

	return [pscustomobject]@{
		Bitmap = New-KmlConvertGuiFallbackMapBitmap
		IsFallback = $true
		TargetObjectName = [string]$targetObject.name
		MapImagePath = $mapImagePath
		CatalogEntry = $mapEntry
		Message = $fallbackReason + ' Using the latitude/longitude grid.'
	}
}

function Get-KmlConvertGuiMapDisplayRectangle {
	param(
		[double]$ViewportWidth,
		[double]$ViewportHeight,
		[double]$ImageWidth,
		[double]$ImageHeight
	)

	if ($ViewportWidth -le 0 -or $ViewportHeight -le 0) {
		throw 'Map viewport dimensions must be greater than zero.'
	}

	if ($ImageWidth -le 0 -or $ImageHeight -le 0) {
		throw 'Map image dimensions must be greater than zero.'
	}

	$viewportAspectRatio = $ViewportWidth / $ViewportHeight
	$imageAspectRatio = $ImageWidth / $ImageHeight
	$displayWidth = $ViewportWidth
	$displayHeight = $ViewportHeight
	$displayX = 0.0
	$displayY = 0.0

	if ($viewportAspectRatio -gt $imageAspectRatio) {
		$displayWidth = $ViewportHeight * $imageAspectRatio
		$displayX = ($ViewportWidth - $displayWidth) / 2
	} else {
		$displayHeight = $ViewportWidth / $imageAspectRatio
		$displayY = ($ViewportHeight - $displayHeight) / 2
	}

	return New-Object System.Drawing.RectangleF(
		[single]$displayX,
		[single]$displayY,
		[single]$displayWidth,
		[single]$displayHeight
	)
}

function Convert-KmlConvertGuiMapPointToAnchor {
	param(
		[double]$PointX,
		[double]$PointY,
		[System.Drawing.RectangleF]$DisplayRectangle
	)

	$rightEdge = [double]$DisplayRectangle.X + [double]$DisplayRectangle.Width
	$bottomEdge = [double]$DisplayRectangle.Y + [double]$DisplayRectangle.Height

	if (
		$PointX -lt $DisplayRectangle.X -or
		$PointX -gt $rightEdge -or
		$PointY -lt $DisplayRectangle.Y -or
		$PointY -gt $bottomEdge
	) {
		return $null
	}

	$normalizedX = ($PointX - $DisplayRectangle.X) / $DisplayRectangle.Width
	$normalizedY = ($PointY - $DisplayRectangle.Y) / $DisplayRectangle.Height
	$normalizedX = [Math]::Max(0.0, [Math]::Min(1.0, $normalizedX))
	$normalizedY = [Math]::Max(0.0, [Math]::Min(1.0, $normalizedY))

	return [pscustomobject]@{
		Latitude = 90.0 - ($normalizedY * 180.0)
		Longitude = ($normalizedX * 360.0) - 180.0
	}
}

function Convert-KmlConvertGuiAnchorToMapPoint {
	param(
		[double]$Latitude,
		[double]$Longitude,
		[System.Drawing.RectangleF]$DisplayRectangle
	)

	if ($Latitude -lt -90 -or $Latitude -gt 90) {
		throw 'Anchor latitude must be between -90 and 90.'
	}

	if ($Longitude -lt -180 -or $Longitude -gt 180) {
		throw 'Anchor longitude must be between -180 and 180.'
	}

	return New-Object System.Drawing.PointF(
		[single]($DisplayRectangle.X + (($Longitude + 180.0) / 360.0 * $DisplayRectangle.Width)),
		[single]($DisplayRectangle.Y + ((90.0 - $Latitude) / 180.0 * $DisplayRectangle.Height))
	)
}

function Convert-KmlConvertGuiCoordinateToText {
	param(
		[double]$Coordinate
	)

	return $Coordinate.ToString('0.######', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Convert-KmlConvertGuiNumberText {
	param(
		[string]$ValueText,
		[string]$FieldLabel
	)

	$trimmedValue = ''
	$parsedValue = 0.0
	$numberStyles = [System.Globalization.NumberStyles]::Float -bor [System.Globalization.NumberStyles]::AllowThousands

	if ($null -eq $ValueText) {
		return $null
	}

	$trimmedValue = $ValueText.Trim()

	if ($trimmedValue -eq '') {
		return $null
	}

	if (-not [double]::TryParse(
		$trimmedValue,
		$numberStyles,
		[System.Globalization.CultureInfo]::InvariantCulture,
		[ref]$parsedValue
	)) {
		throw $FieldLabel + ' must be numeric when provided.'
	}

	if ([double]::IsNaN($parsedValue) -or [double]::IsInfinity($parsedValue)) {
		throw $FieldLabel + ' must be finite.'
	}

	return $parsedValue
}

function Resolve-KmlConvertGuiAnchorTextValues {
	param(
		[string]$AnchorLatitudeText,
		[string]$AnchorLongitudeText
	)

	$anchorLatitude = Convert-KmlConvertGuiNumberText -ValueText $AnchorLatitudeText -FieldLabel 'Anchor latitude'
	$anchorLongitude = Convert-KmlConvertGuiNumberText -ValueText $AnchorLongitudeText -FieldLabel 'Anchor longitude'

	if (($null -eq $anchorLatitude) -ne ($null -eq $anchorLongitude)) {
		throw 'Anchor latitude and longitude must be provided together.'
	}

	if ($null -eq $anchorLatitude) {
		return $null
	}

	if ($anchorLatitude -lt -90 -or $anchorLatitude -gt 90) {
		throw 'Anchor latitude must be between -90 and 90.'
	}

	if ($anchorLongitude -lt -180 -or $anchorLongitude -gt 180) {
		throw 'Anchor longitude must be between -180 and 180.'
	}

	return [pscustomobject]@{
		Latitude = [double]$anchorLatitude
		Longitude = [double]$anchorLongitude
	}
}

function Convert-KmlConvertGuiKilometersToMetersText {
	param(
		[double]$Kilometers
	)

	$meters = [decimal]$Kilometers * [decimal]1000

	return $meters.ToString('0.###############', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Resolve-KmlConvertGuiTargetSettings {
	param(
		[string]$TargetObjectName,
		[string]$TargetRadiusKmText
	)

	$targetObject = Get-KmlConvertGuiTargetObjectDefinition -TargetObjectName $TargetObjectName
	$customTargetRadiusKm = Convert-KmlConvertGuiNumberText -ValueText $TargetRadiusKmText -FieldLabel 'Custom target radius'
	$resolvedTargetRadiusKm = [double]$targetObject.radiusKm
	$isCustomRadius = $false

	if ($null -ne $customTargetRadiusKm) {
		if ($customTargetRadiusKm -le 0) {
			throw 'Custom target radius must be greater than zero.'
		}

		$resolvedTargetRadiusKm = $customTargetRadiusKm
		$isCustomRadius = $true
	}

	return [pscustomobject]@{
		targetObjectKey = [string]$targetObject.key
		targetObjectName = [string]$targetObject.name
		targetRadiusKm = $resolvedTargetRadiusKm
		targetRadiusMetersText = Convert-KmlConvertGuiKilometersToMetersText -Kilometers $resolvedTargetRadiusKm
		isCustomRadius = $isCustomRadius
	}
}

function Convert-KmlConvertGuiFileNamePart {
	param(
		[string]$ValueText,
		[string]$FieldLabel
	)

	$trimmedValue = ''
	$safeValue = ''

	if ($null -ne $ValueText) {
		$trimmedValue = $ValueText.Trim()
	}

	$safeValue = [regex]::Replace($trimmedValue, '[^A-Za-z0-9]+', '_').Trim('_')

	if ($safeValue -eq '') {
		throw $FieldLabel + ' must contain at least one letter or number.'
	}

	return $safeValue
}

function Convert-KmlConvertGuiRadiusToFileNameToken {
	param(
		[double]$RadiusKm
	)

	$radiusText = $RadiusKm.ToString('0.###############', [System.Globalization.CultureInfo]::InvariantCulture)

	$radiusText = $radiusText.Replace('-', 'neg')
	$radiusText = $radiusText.Replace('.', 'p')
	$radiusText = $radiusText.Replace('+', '')

	return 'trKm' + $radiusText
}

function Convert-KmlConvertGuiCoordinateToFileNameToken {
	param(
		[double]$Coordinate
	)

	$coordinateText = $Coordinate.ToString('0.###############', [System.Globalization.CultureInfo]::InvariantCulture)

	$coordinateText = $coordinateText.Replace('-', 'negative')
	$coordinateText = $coordinateText.Replace('.', 'point')
	$coordinateText = $coordinateText.Replace('+', '')

	return $coordinateText
}

function Convert-KmlConvertGuiAnchorToFileNameToken {
	param(
		[string]$AnchorLatitudeText,
		[string]$AnchorLongitudeText
	)

	$anchorValues = Resolve-KmlConvertGuiAnchorTextValues `
		-AnchorLatitudeText $AnchorLatitudeText `
		-AnchorLongitudeText $AnchorLongitudeText

	if ($null -eq $anchorValues) {
		throw 'Anchor filename option requires an anchor latitude and longitude.'
	}

	return (
		'anchor_' +
		(Convert-KmlConvertGuiCoordinateToFileNameToken -Coordinate $anchorValues.Latitude) +
		'_' +
		(Convert-KmlConvertGuiCoordinateToFileNameToken -Coordinate $anchorValues.Longitude)
	)
}

function Resolve-KmlConvertGuiOutputPath {
	param(
		[string]$RequestedOutputPath,
		[string]$TargetObjectName,
		[string]$TargetRadiusKmText,
		[bool]$IncludeTargetRadiusSuffix,
		[string]$AnchorLatitudeText,
		[string]$AnchorLongitudeText,
		[bool]$IncludeAnchorSuffix
	)

	$trimmedOutputPath = ''
	$outputDirectory = ''
	$chosenStem = ''
	$safeChosenStem = ''
	$targetSettings = $null
	$fileNameParts = @()
	$finalFileName = ''

	if ($null -ne $RequestedOutputPath) {
		$trimmedOutputPath = $RequestedOutputPath.Trim()
	}

	if ($trimmedOutputPath -eq '') {
		throw 'Output KML path is required.'
	}

	$outputDirectory = [System.IO.Path]::GetDirectoryName($trimmedOutputPath)
	$chosenStem = [System.IO.Path]::GetFileNameWithoutExtension($trimmedOutputPath)
	$safeChosenStem = Convert-KmlConvertGuiFileNamePart -ValueText $chosenStem -FieldLabel 'Output filename'
	$targetSettings = Resolve-KmlConvertGuiTargetSettings `
		-TargetObjectName $TargetObjectName `
		-TargetRadiusKmText $TargetRadiusKmText
	$fileNameParts = @($safeChosenStem)

	if ($IncludeAnchorSuffix) {
		$fileNameParts += Convert-KmlConvertGuiAnchorToFileNameToken `
			-AnchorLatitudeText $AnchorLatitudeText `
			-AnchorLongitudeText $AnchorLongitudeText
	}

	$fileNameParts += $targetSettings.targetObjectKey
	$fileNameParts += 'greatCircle'

	if ($IncludeTargetRadiusSuffix) {
		$fileNameParts += Convert-KmlConvertGuiRadiusToFileNameToken -RadiusKm $targetSettings.targetRadiusKm
	}

	$finalFileName = ($fileNameParts -join '_') + '.kml'

	if ($outputDirectory -eq '') {
		return $finalFileName
	}

	return Join-Path $outputDirectory $finalFileName
}

function Convert-KmlConvertGuiRequiredText {
	param(
		[string]$ValueText,
		[string]$ValueLabel
	)

	if ($null -eq $ValueText -or $ValueText.Trim() -eq '') {
		throw 'Digistar script generation requires ' + $ValueLabel + '.'
	}

	return $ValueText
}

function Convert-KmlConvertGuiDigistarNamePart {
	param(
		[string]$ValueText,
		[string]$ValueLabel
	)

	$rawText = Convert-KmlConvertGuiRequiredText -ValueText $ValueText -ValueLabel $ValueLabel
	$spacedText = [regex]::Replace($rawText, '[^A-Za-z0-9]+', ' ').Trim()
	$resultText = ''
	$index = 0

	if ($spacedText -eq '') {
		throw 'Digistar script generation requires a valid ' + $ValueLabel + '.'
	}

	$words = @($spacedText -split '\s+')

	for ($index = 0; $index -lt $words.Count; $index += 1) {
		$currentWord = [string]$words[$index]

		if ($currentWord -ceq $currentWord.ToUpperInvariant()) {
			$currentWord = $currentWord.ToLowerInvariant()
		}

		if ($index -eq 0) {
			$resultText += $currentWord.Substring(0, 1).ToLowerInvariant() + $currentWord.Substring(1)
		} else {
			$resultText += $currentWord.Substring(0, 1).ToUpperInvariant() + $currentWord.Substring(1)
		}
	}

	if ($resultText -eq '') {
		throw 'Digistar script generation requires a valid ' + $ValueLabel + '.'
	}

	return $resultText
}

function Convert-KmlConvertGuiUnsignedIntegerToBase36 {
	param(
		[uint64]$Value
	)

	$characters = '0123456789abcdefghijklmnopqrstuvwxyz'
	$resultText = ''

	if ($Value -eq 0) {
		return '0'
	}

	while ($Value -gt 0) {
		$remainder = [int]($Value % 36)
		$resultText = [string]$characters[$remainder] + $resultText
		$Value = [uint64][Math]::Floor($Value / 36)
	}

	return $resultText
}

function Get-KmlConvertGuiStableDigistarHash {
	param(
		[string]$ValueText
	)

	$requiredText = Convert-KmlConvertGuiRequiredText -ValueText $ValueText -ValueLabel 'stable hash input'
	[uint64]$hashValue = 2166136261
	[uint64]$hashModulus = 4294967296
	$index = 0

	for ($index = 0; $index -lt $requiredText.Length; $index += 1) {
		$hashValue = $hashValue -bxor [uint64][int][char]$requiredText[$index]
		$hashValue = ($hashValue * [uint64]16777619) % $hashModulus
	}

	$hashText = Convert-KmlConvertGuiUnsignedIntegerToBase36 -Value $hashValue

	while ($hashText.Length -lt $script:kmlConvertGuiConfig.digistar.stableHashLength) {
		$hashText = '0' + $hashText
	}

	return $hashText.Substring($hashText.Length - $script:kmlConvertGuiConfig.digistar.stableHashLength)
}

function Test-KmlConvertGuiDigistarObjectName {
	param(
		[string]$ObjectName
	)

	return (
		$null -ne $ObjectName -and
		$ObjectName.Length -le $script:kmlConvertGuiConfig.digistar.maximumObjectNameLength -and
		$ObjectName -cmatch '^[A-Za-z][A-Za-z0-9]*$'
	)
}

function Test-KmlConvertGuiUsedDigistarObjectNameStem {
	param(
		[string]$ObjectNameStem,
		[string[]]$UsedObjectNameStems
	)

	$index = 0

	if ($null -eq $UsedObjectNameStems) {
		return $false
	}

	for ($index = 0; $index -lt $UsedObjectNameStems.Count; $index += 1) {
		if ([string]::Equals(
			$ObjectNameStem,
			[string]$UsedObjectNameStems[$index],
			[System.StringComparison]::OrdinalIgnoreCase
		)) {
			return $true
		}
	}

	return $false
}

function Test-KmlConvertGuiUsedDigistarScriptPath {
	param(
		[string]$ScriptPath,
		[string[]]$UsedScriptPaths
	)

	$absoluteScriptPath = [System.IO.Path]::GetFullPath($ScriptPath)
	$index = 0

	if (Test-Path -LiteralPath $absoluteScriptPath) {
		return $true
	}

	if ($null -eq $UsedScriptPaths) {
		return $false
	}

	for ($index = 0; $index -lt $UsedScriptPaths.Count; $index += 1) {
		if ([string]::Equals(
			$absoluteScriptPath,
			[System.IO.Path]::GetFullPath([string]$UsedScriptPaths[$index]),
			[System.StringComparison]::OrdinalIgnoreCase
		)) {
			return $true
		}
	}

	return $false
}

function New-KmlConvertGuiDigistarCollisionFileName {
	param(
		[string]$FileName,
		[string]$StableHash
	)

	$fileNameWithoutExtension = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
	$extension = [System.IO.Path]::GetExtension($FileName)
	$actionSuffix = ''
	$baseName = $fileNameWithoutExtension

	if ($baseName.EndsWith('_on', [System.StringComparison]::Ordinal)) {
		$actionSuffix = '_on'
		$baseName = $baseName.Substring(0, $baseName.Length - 3)
	} elseif ($baseName.EndsWith('_off', [System.StringComparison]::Ordinal)) {
		$actionSuffix = '_off'
		$baseName = $baseName.Substring(0, $baseName.Length - 4)
	} else {
		throw 'Digistar script filename must end with _on or _off: ' + $FileName
	}

	return $baseName + '_' + $StableHash + $actionSuffix + $extension
}

function New-KmlConvertGuiDigistarScriptPlan {
	param(
		[string]$ConvertedKmlPath,
		[string]$OriginalKmlPath,
		[string]$TargetObjectName,
		[string]$TargetRadiusKmText,
		[string[]]$UsedObjectNameStems,
		[string[]]$UsedScriptPaths,
		[bool]$AllowMissingOutputDirectory = $false
	)

	$requiredConvertedKmlPath = Convert-KmlConvertGuiRequiredText -ValueText $ConvertedKmlPath -ValueLabel 'converted KML path'
	$requiredOriginalKmlPath = Convert-KmlConvertGuiRequiredText -ValueText $OriginalKmlPath -ValueLabel 'original KML filename'
	$absoluteConvertedKmlPath = [System.IO.Path]::GetFullPath($requiredConvertedKmlPath)
	$outputDirectory = [System.IO.Path]::GetDirectoryName($absoluteConvertedKmlPath)
	$originalBaseName = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetFileName($requiredOriginalKmlPath))
	$sourcePrefixLength = [Math]::Min(15, $originalBaseName.Length)
	$sourcePrefix = $originalBaseName.Substring(0, $sourcePrefixLength)
	$targetObject = Get-KmlConvertGuiTargetObjectDefinition -TargetObjectName $TargetObjectName
	$targetObjectPart = Convert-KmlConvertGuiDigistarNamePart -ValueText $targetObject.key -ValueLabel 'target object'
	$originalFilePart = Convert-KmlConvertGuiDigistarNamePart -ValueText $sourcePrefix -ValueLabel 'first 15 characters of the original KML filename'
	$methodPart = Convert-KmlConvertGuiDigistarNamePart -ValueText $script:kmlConvertGuiConfig.digistar.methodName -ValueLabel 'map projection'
	$optionsPart = [string]$script:kmlConvertGuiConfig.digistar.reservedOptionsPart
	$readableObjectNameStem = (
		$targetObjectPart +
		$originalFilePart.Substring(0, 1).ToUpperInvariant() +
		$originalFilePart.Substring(1) +
		$methodPart.Substring(0, 1).ToUpperInvariant() +
		$methodPart.Substring(1) +
		$optionsPart.Substring(0, 1).ToUpperInvariant() +
		$optionsPart.Substring(1)
	)
	$maximumObjectNameStemLength = (
		$script:kmlConvertGuiConfig.digistar.maximumPlanetCopyObjectLength -
		$script:kmlConvertGuiConfig.digistar.planetCopySuffix.Length
	)
	$objectNameStemLength = [Math]::Min($maximumObjectNameStemLength, $readableObjectNameStem.Length)
	$objectNameStem = $readableObjectNameStem.Substring(0, $objectNameStemLength)
	$hasObjectNameCollision = Test-KmlConvertGuiUsedDigistarObjectNameStem `
		-ObjectNameStem $objectNameStem `
		-UsedObjectNameStems $UsedObjectNameStems

	if ($hasObjectNameCollision) {
		$stableHash = Get-KmlConvertGuiStableDigistarHash -ValueText ($readableObjectNameStem + '|' + $requiredOriginalKmlPath)
		$objectNameStem = (
			$objectNameStem.Substring(0, $maximumObjectNameStemLength - $stableHash.Length) +
			$stableHash
		)
		$hasObjectNameCollision = Test-KmlConvertGuiUsedDigistarObjectNameStem `
			-ObjectNameStem $objectNameStem `
			-UsedObjectNameStems $UsedObjectNameStems
	}

	if ($hasObjectNameCollision) {
		throw 'Digistar object-name collision remains after applying the stable hash.'
	}

	$planetCopyObjectName = $objectNameStem + $script:kmlConvertGuiConfig.digistar.planetCopySuffix
	$kmlObjectName = $objectNameStem + $script:kmlConvertGuiConfig.digistar.kmlObjectSuffix

	if (-not (Test-KmlConvertGuiDigistarObjectName -ObjectName $planetCopyObjectName)) {
		throw 'Generated Digistar planet-copy object name is invalid: ' + $planetCopyObjectName
	}

	if (-not (Test-KmlConvertGuiDigistarObjectName -ObjectName $kmlObjectName)) {
		throw 'Generated Digistar KML object name is invalid: ' + $kmlObjectName
	}

	if (
		-not $AllowMissingOutputDirectory -and
		-not (Test-Path -LiteralPath $outputDirectory -PathType Container)
	) {
		throw 'Digistar script output directory does not exist: ' + $outputDirectory
	}

	$onFileName = $targetObjectPart + '_' + $originalFilePart + '_' + $methodPart + '_' + $optionsPart + '_on.ds'
	$offFileName = $targetObjectPart + '_' + $originalFilePart + '_' + $methodPart + '_' + $optionsPart + '_off.ds'
	$onScriptPath = Join-Path $outputDirectory $onFileName
	$offScriptPath = Join-Path $outputDirectory $offFileName
	$hasScriptFileNameCollision = (
		(Test-KmlConvertGuiUsedDigistarScriptPath -ScriptPath $onScriptPath -UsedScriptPaths $UsedScriptPaths) -or
		(Test-KmlConvertGuiUsedDigistarScriptPath -ScriptPath $offScriptPath -UsedScriptPaths $UsedScriptPaths)
	)

	if ($hasScriptFileNameCollision) {
		$stableHash = Get-KmlConvertGuiStableDigistarHash -ValueText $absoluteConvertedKmlPath
		$onScriptPath = Join-Path $outputDirectory (
			New-KmlConvertGuiDigistarCollisionFileName -FileName $onFileName -StableHash $stableHash
		)
		$offScriptPath = Join-Path $outputDirectory (
			New-KmlConvertGuiDigistarCollisionFileName -FileName $offFileName -StableHash $stableHash
		)
		$hasScriptFileNameCollision = (
			(Test-KmlConvertGuiUsedDigistarScriptPath -ScriptPath $onScriptPath -UsedScriptPaths $UsedScriptPaths) -or
			(Test-KmlConvertGuiUsedDigistarScriptPath -ScriptPath $offScriptPath -UsedScriptPaths $UsedScriptPaths)
		)
	}

	if ($hasScriptFileNameCollision) {
		throw 'Digistar script filename collision remains after applying the stable hash.'
	}

	$targetSettings = Resolve-KmlConvertGuiTargetSettings `
		-TargetObjectName $TargetObjectName `
		-TargetRadiusKmText $TargetRadiusKmText
	$radiusExpression = 'r' + $targetObject.key

	if ($targetSettings.isCustomRadius) {
		$radiusExpression = (
			$targetSettings.targetRadiusKm.ToString(
				'0.###############',
				[System.Globalization.CultureInfo]::InvariantCulture
			) +
			' km'
		)
	}

	return [pscustomobject]@{
		OutputDirectory = $outputDirectory
		ConvertedKmlPath = $absoluteConvertedKmlPath
		OnScriptPath = [System.IO.Path]::GetFullPath($onScriptPath)
		OffScriptPath = [System.IO.Path]::GetFullPath($offScriptPath)
		ObjectNameStem = $objectNameStem
		PlanetCopyObjectName = $planetCopyObjectName
		KmlObjectName = $kmlObjectName
		TargetObjectKey = [string]$targetObject.key
		RadiusExpression = $radiusExpression
	}
}

function Get-KmlConvertGuiDigistarTemplatePaths {
	param(
		[string]$TemplateDirectory
	)

	if ($null -eq $TemplateDirectory -or $TemplateDirectory.Trim() -eq '') {
		$TemplateDirectory = Join-Path $PSScriptRoot $script:kmlConvertGuiConfig.digistar.templateDirectoryName
	}

	$absoluteTemplateDirectory = [System.IO.Path]::GetFullPath($TemplateDirectory)

	return [pscustomobject]@{
		TemplateDirectory = $absoluteTemplateDirectory
		AddTemplatePath = Join-Path $absoluteTemplateDirectory $script:kmlConvertGuiConfig.digistar.addTemplateFileName
		RemoveTemplatePath = Join-Path $absoluteTemplateDirectory $script:kmlConvertGuiConfig.digistar.removeTemplateFileName
	}
}

function Read-KmlConvertGuiDigistarTemplates {
	param(
		[string]$TemplateDirectory
	)

	$templatePaths = Get-KmlConvertGuiDigistarTemplatePaths -TemplateDirectory $TemplateDirectory

	if (-not (Test-Path -LiteralPath $templatePaths.AddTemplatePath -PathType Leaf)) {
		throw 'Missing Digistar add script template: ' + $templatePaths.AddTemplatePath
	}

	if (-not (Test-Path -LiteralPath $templatePaths.RemoveTemplatePath -PathType Leaf)) {
		throw 'Missing Digistar remove script template: ' + $templatePaths.RemoveTemplatePath
	}

	$addTemplateText = [System.IO.File]::ReadAllText($templatePaths.AddTemplatePath)
	$removeTemplateText = [System.IO.File]::ReadAllText($templatePaths.RemoveTemplatePath)

	if ($addTemplateText -eq '') {
		throw 'Digistar add script template is empty: ' + $templatePaths.AddTemplatePath
	}

	if ($removeTemplateText -eq '') {
		throw 'Digistar remove script template is empty: ' + $templatePaths.RemoveTemplatePath
	}

	return [pscustomobject]@{
		AddTemplateText = $addTemplateText
		RemoveTemplateText = $removeTemplateText
		Paths = $templatePaths
	}
}

function Convert-KmlConvertGuiDigistarTemplate {
	param(
		[string]$TemplateText,
		[System.Collections.IDictionary]$ReplacementValues,
		[string]$TemplateLabel
	)

	if ($null -eq $TemplateText -or $TemplateText -eq '') {
		throw 'Digistar ' + $TemplateLabel + ' script template is empty.'
	}

	$renderedText = $TemplateText

	foreach ($placeholderEntry in $script:kmlConvertGuiConfig.digistar.placeholders.GetEnumerator()) {
		$replacementValue = Convert-KmlConvertGuiRequiredText `
			-ValueText ([string]$ReplacementValues[$placeholderEntry.Key]) `
			-ValueLabel ([string]$placeholderEntry.Key)
		$renderedText = $renderedText.Replace([string]$placeholderEntry.Value, $replacementValue)
	}

	if ($renderedText.Contains('{{')) {
		throw 'Unresolved placeholder in Digistar ' + $TemplateLabel + ' script template.'
	}

	return $renderedText
}

function New-KmlConvertGuiDigistarScriptContents {
	param(
		[pscustomobject]$ScriptPlan,
		[pscustomobject]$Templates
	)

	if ($null -eq $ScriptPlan -or $null -eq $Templates) {
		throw 'Digistar script rendering requires a script plan and templates.'
	}

	$replacementValues = [ordered]@{
		convertedKmlPath = [string]$ScriptPlan.ConvertedKmlPath
		targetObject = [string]$ScriptPlan.TargetObjectKey
		planetCopyObjectName = [string]$ScriptPlan.PlanetCopyObjectName
		kmlObjectName = [string]$ScriptPlan.KmlObjectName
		radiusExpression = [string]$ScriptPlan.RadiusExpression
	}

	return [pscustomobject]@{
		OnScriptText = Convert-KmlConvertGuiDigistarTemplate `
			-TemplateText $Templates.AddTemplateText `
			-ReplacementValues $replacementValues `
			-TemplateLabel 'add'
		OffScriptText = Convert-KmlConvertGuiDigistarTemplate `
			-TemplateText $Templates.RemoveTemplateText `
			-ReplacementValues $replacementValues `
			-TemplateLabel 'remove'
	}
}

function Write-KmlConvertGuiDigistarScripts {
	param(
		[pscustomobject]$ScriptPlan,
		[pscustomobject]$ScriptContents
	)

	if ($null -eq $ScriptPlan -or $null -eq $ScriptContents) {
		throw 'Digistar script writing requires a script plan and rendered content.'
	}

	$outputDirectory = [System.IO.Path]::GetFullPath([string]$ScriptPlan.OutputDirectory)
	$onScriptPath = [System.IO.Path]::GetFullPath([string]$ScriptPlan.OnScriptPath)
	$offScriptPath = [System.IO.Path]::GetFullPath([string]$ScriptPlan.OffScriptPath)

	if (
		-not [string]::Equals(
			[System.IO.Path]::GetDirectoryName($onScriptPath),
			$outputDirectory,
			[System.StringComparison]::OrdinalIgnoreCase
		) -or
		-not [string]::Equals(
			[System.IO.Path]::GetDirectoryName($offScriptPath),
			$outputDirectory,
			[System.StringComparison]::OrdinalIgnoreCase
		)
	) {
		throw 'Digistar scripts must be saved beside the converted KML file.'
	}

	if (
		-not [System.IO.Path]::GetExtension($onScriptPath).Equals('.ds', [System.StringComparison]::OrdinalIgnoreCase) -or
		-not [System.IO.Path]::GetExtension($offScriptPath).Equals('.ds', [System.StringComparison]::OrdinalIgnoreCase)
	) {
		throw 'Digistar script output paths must use the .ds extension.'
	}

	if ([string]::Equals($onScriptPath, $offScriptPath, [System.StringComparison]::OrdinalIgnoreCase)) {
		throw 'Digistar on and off script paths must be different.'
	}

	if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
		throw 'Digistar script output directory does not exist: ' + $outputDirectory
	}

	if (Test-Path -LiteralPath $onScriptPath) {
		throw 'Digistar on script path already exists: ' + $onScriptPath
	}

	if (Test-Path -LiteralPath $offScriptPath) {
		throw 'Digistar off script path already exists: ' + $offScriptPath
	}

	$onScriptText = Convert-KmlConvertGuiRequiredText `
		-ValueText ([string]$ScriptContents.OnScriptText) `
		-ValueLabel 'rendered on script content'
	$offScriptText = Convert-KmlConvertGuiRequiredText `
		-ValueText ([string]$ScriptContents.OffScriptText) `
		-ValueLabel 'rendered off script content'
	$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
	[System.IO.File]::WriteAllText($onScriptPath, $onScriptText, $utf8WithoutBom)
	[System.IO.File]::WriteAllText($offScriptPath, $offScriptText, $utf8WithoutBom)

	return [pscustomobject]@{
		OnScriptPath = $onScriptPath
		OffScriptPath = $offScriptPath
		ObjectNameStem = [string]$ScriptPlan.ObjectNameStem
		PlanetCopyObjectName = [string]$ScriptPlan.PlanetCopyObjectName
		KmlObjectName = [string]$ScriptPlan.KmlObjectName
		RadiusExpression = [string]$ScriptPlan.RadiusExpression
	}
}

function Invoke-KmlConvertGuiDigistarScriptGeneration {
	param(
		[bool]$Enabled,
		[string]$ConvertedKmlPath,
		[string]$OriginalKmlPath,
		[string]$TargetObjectName,
		[string]$TargetRadiusKmText,
		[string]$TemplateDirectory,
		[string[]]$UsedObjectNameStems,
		[string[]]$UsedScriptPaths
	)

	if (-not $Enabled) {
		return $null
	}

	try {
		if (-not (Test-Path -LiteralPath $ConvertedKmlPath -PathType Leaf)) {
			throw 'Converted KML file not found: ' + $ConvertedKmlPath
		}

		$scriptPlan = New-KmlConvertGuiDigistarScriptPlan `
			-ConvertedKmlPath $ConvertedKmlPath `
			-OriginalKmlPath $OriginalKmlPath `
			-TargetObjectName $TargetObjectName `
			-TargetRadiusKmText $TargetRadiusKmText `
			-UsedObjectNameStems $UsedObjectNameStems `
			-UsedScriptPaths $UsedScriptPaths
		$templates = Read-KmlConvertGuiDigistarTemplates -TemplateDirectory $TemplateDirectory
		$scriptContents = New-KmlConvertGuiDigistarScriptContents -ScriptPlan $scriptPlan -Templates $templates
		return Write-KmlConvertGuiDigistarScripts -ScriptPlan $scriptPlan -ScriptContents $scriptContents
	} catch {
		throw 'Digistar script generation failed after KML conversion: ' + $_.Exception.Message
	}
}

function Test-KmlConvertGuiPathWithinDirectory {
	param(
		[string]$CandidatePath,
		[string]$DirectoryPath,
		[bool]$IncludeDirectory = $true
	)

	$absoluteCandidatePath = [System.IO.Path]::GetFullPath(
		(Convert-KmlConvertGuiRequiredText -ValueText $CandidatePath -ValueLabel 'candidate path')
	)
	$absoluteDirectoryPath = [System.IO.Path]::GetFullPath(
		(Convert-KmlConvertGuiRequiredText -ValueText $DirectoryPath -ValueLabel 'directory path')
	)
	$directoryPrefix = $absoluteDirectoryPath

	if (
		$directoryPrefix.EndsWith([string][System.IO.Path]::DirectorySeparatorChar) -or
		$directoryPrefix.EndsWith([string][System.IO.Path]::AltDirectorySeparatorChar)
	) {
		$directoryPrefix = $directoryPrefix.TrimEnd(
			[System.IO.Path]::DirectorySeparatorChar,
			[System.IO.Path]::AltDirectorySeparatorChar
		)
	}

	if (
		[string]::Equals(
			$absoluteCandidatePath.TrimEnd(
				[System.IO.Path]::DirectorySeparatorChar,
				[System.IO.Path]::AltDirectorySeparatorChar
			),
			$directoryPrefix,
			[System.StringComparison]::OrdinalIgnoreCase
		)
	) {
		return $IncludeDirectory
	}

	$directoryPrefix += [System.IO.Path]::DirectorySeparatorChar

	return $absoluteCandidatePath.StartsWith(
		$directoryPrefix,
		[System.StringComparison]::OrdinalIgnoreCase
	)
}

function Get-KmlConvertGuiBatchInputFiles {
	param(
		[string]$InputFolderPath,
		[string]$OutputFolderPath,
		[bool]$Recursive
	)

	$requiredInputFolderPath = Convert-KmlConvertGuiRequiredText `
		-ValueText $InputFolderPath `
		-ValueLabel 'input folder path'
	$requiredOutputFolderPath = Convert-KmlConvertGuiRequiredText `
		-ValueText $OutputFolderPath `
		-ValueLabel 'output folder path'
	$absoluteInputFolderPath = [System.IO.Path]::GetFullPath($requiredInputFolderPath)
	$absoluteOutputFolderPath = [System.IO.Path]::GetFullPath($requiredOutputFolderPath)
	$directoriesToSearch = New-Object 'System.Collections.Generic.Stack[string]'
	$inputFileList = New-Object System.Collections.ArrayList
	[string[]]$sortedInputFiles = @()

	if (-not (Test-Path -LiteralPath $absoluteInputFolderPath -PathType Container)) {
		throw 'Input folder not found: ' + $absoluteInputFolderPath
	}

	if (
		[string]::Equals(
			$absoluteInputFolderPath.TrimEnd('\', '/'),
			$absoluteOutputFolderPath.TrimEnd('\', '/'),
			[System.StringComparison]::OrdinalIgnoreCase
		)
	) {
		throw 'Output folder must differ from the input folder.'
	}

	$directoriesToSearch.Push($absoluteInputFolderPath)

	while ($directoriesToSearch.Count -gt 0) {
		$currentDirectoryPath = $directoriesToSearch.Pop()

		foreach (
			$currentFilePath in
			[System.IO.Directory]::EnumerateFiles(
				$currentDirectoryPath,
				'*',
				[System.IO.SearchOption]::TopDirectoryOnly
			)
		) {
			if (
				[System.IO.Path]::GetExtension($currentFilePath).Equals(
					'.kml',
					[System.StringComparison]::OrdinalIgnoreCase
				)
			) {
				[void]$inputFileList.Add([System.IO.Path]::GetFullPath($currentFilePath))
			}
		}

		if ($Recursive) {
			foreach (
				$childDirectoryPath in
				[System.IO.Directory]::EnumerateDirectories(
					$currentDirectoryPath,
					'*',
					[System.IO.SearchOption]::TopDirectoryOnly
				)
			) {
				if (
					-not (Test-KmlConvertGuiPathWithinDirectory `
						-CandidatePath $childDirectoryPath `
						-DirectoryPath $absoluteOutputFolderPath `
						-IncludeDirectory $true)
				) {
					$directoriesToSearch.Push(
						[System.IO.Path]::GetFullPath($childDirectoryPath)
					)
				}
			}
		}
	}

	$sortedInputFiles = [string[]]@($inputFileList)
	[System.Array]::Sort($sortedInputFiles, [System.StringComparer]::OrdinalIgnoreCase)

	return ,$sortedInputFiles
}

function New-KmlConvertGuiBatchPlan {
	param(
		[string]$InputFolderPath,
		[string]$OutputFolderPath,
		[bool]$Recursive,
		[string]$TargetObjectName,
		[string]$TargetRadiusKmText,
		[string]$SourceRadiusKmText,
		[string]$AnchorLatitudeText,
		[string]$AnchorLongitudeText,
		[bool]$IncludeTargetRadiusSuffix,
		[bool]$IncludeAnchorSuffix,
		[bool]$CreateDigistarScripts
	)

	$absoluteInputFolderPath = [System.IO.Path]::GetFullPath(
		(Convert-KmlConvertGuiRequiredText -ValueText $InputFolderPath -ValueLabel 'input folder path')
	)
	$absoluteOutputFolderPath = [System.IO.Path]::GetFullPath(
		(Convert-KmlConvertGuiRequiredText -ValueText $OutputFolderPath -ValueLabel 'output folder path')
	)
	$targetSettings = Resolve-KmlConvertGuiTargetSettings `
		-TargetObjectName $TargetObjectName `
		-TargetRadiusKmText $TargetRadiusKmText
	$sourceRadiusKm = Convert-KmlConvertGuiNumberText `
		-ValueText $SourceRadiusKmText `
		-FieldLabel 'Source radius'
	$anchorValues = Resolve-KmlConvertGuiAnchorTextValues `
		-AnchorLatitudeText $AnchorLatitudeText `
		-AnchorLongitudeText $AnchorLongitudeText
	$normalizedTargetRadiusKmText = ''
	$normalizedSourceRadiusKmText = ''
	$normalizedAnchorLatitudeText = ''
	$normalizedAnchorLongitudeText = ''
	$inputFiles = Get-KmlConvertGuiBatchInputFiles `
		-InputFolderPath $absoluteInputFolderPath `
		-OutputFolderPath $absoluteOutputFolderPath `
		-Recursive $Recursive
	$inputFolderPrefix = $absoluteInputFolderPath
	$batchItems = New-Object System.Collections.ArrayList
	$existingOutputPaths = New-Object System.Collections.ArrayList
	$outputPathKeys = @{}
	$usedObjectNameStems = @()
	$usedScriptPaths = @()
	$index = 0

	if ($null -ne $sourceRadiusKm -and $sourceRadiusKm -le 0) {
		throw 'Source radius must be greater than zero.'
	}

	if ($targetSettings.isCustomRadius) {
		$normalizedTargetRadiusKmText = $targetSettings.targetRadiusKm.ToString(
			'0.###############',
			[System.Globalization.CultureInfo]::InvariantCulture
		)
	}

	if ($null -ne $sourceRadiusKm) {
		$normalizedSourceRadiusKmText = $sourceRadiusKm.ToString(
			'0.###############',
			[System.Globalization.CultureInfo]::InvariantCulture
		)
	}

	if ($null -ne $anchorValues) {
		$normalizedAnchorLatitudeText = $anchorValues.Latitude.ToString(
			'0.###############',
			[System.Globalization.CultureInfo]::InvariantCulture
		)
		$normalizedAnchorLongitudeText = $anchorValues.Longitude.ToString(
			'0.###############',
			[System.Globalization.CultureInfo]::InvariantCulture
		)
	}

	if (
		-not $inputFolderPrefix.EndsWith([string][System.IO.Path]::DirectorySeparatorChar) -and
		-not $inputFolderPrefix.EndsWith([string][System.IO.Path]::AltDirectorySeparatorChar)
	) {
		$inputFolderPrefix += [System.IO.Path]::DirectorySeparatorChar
	}

	for ($index = 0; $index -lt $inputFiles.Count; $index += 1) {
		$sourcePath = [System.IO.Path]::GetFullPath([string]$inputFiles[$index])
		$relativeSourcePath = $sourcePath.Substring($inputFolderPrefix.Length)
		$relativeDirectory = [System.IO.Path]::GetDirectoryName($relativeSourcePath)
		$itemOutputDirectory = $absoluteOutputFolderPath

		if ($relativeDirectory -ne '') {
			$itemOutputDirectory = Join-Path $absoluteOutputFolderPath $relativeDirectory
		}

		$requestedOutputPath = Join-Path $itemOutputDirectory ([System.IO.Path]::GetFileName($sourcePath))
		$resolvedOutputPath = [System.IO.Path]::GetFullPath(
			(Resolve-KmlConvertGuiOutputPath `
				-RequestedOutputPath $requestedOutputPath `
				-TargetObjectName $targetSettings.targetObjectName `
				-TargetRadiusKmText $normalizedTargetRadiusKmText `
				-IncludeTargetRadiusSuffix $IncludeTargetRadiusSuffix `
				-AnchorLatitudeText $normalizedAnchorLatitudeText `
				-AnchorLongitudeText $normalizedAnchorLongitudeText `
				-IncludeAnchorSuffix $IncludeAnchorSuffix)
		)
		$outputPathKey = $resolvedOutputPath.ToLowerInvariant()

		if ($outputPathKeys.ContainsKey($outputPathKey)) {
			throw (
				'Batch output collision: ' +
				$sourcePath +
				' and ' +
				[string]$outputPathKeys[$outputPathKey] +
				' both resolve to ' +
				$resolvedOutputPath
			)
		}

		$outputPathKeys[$outputPathKey] = $sourcePath

		if (Test-Path -LiteralPath $resolvedOutputPath) {
			[void]$existingOutputPaths.Add($resolvedOutputPath)
		}

		$digistarScriptPlan = $null

		if ($CreateDigistarScripts) {
			$digistarScriptPlan = New-KmlConvertGuiDigistarScriptPlan `
				-ConvertedKmlPath $resolvedOutputPath `
				-OriginalKmlPath $sourcePath `
				-TargetObjectName $targetSettings.targetObjectName `
				-TargetRadiusKmText $normalizedTargetRadiusKmText `
				-UsedObjectNameStems $usedObjectNameStems `
				-UsedScriptPaths $usedScriptPaths `
				-AllowMissingOutputDirectory $true
			$usedObjectNameStems += [string]$digistarScriptPlan.ObjectNameStem
			$usedScriptPaths += [string]$digistarScriptPlan.OnScriptPath
			$usedScriptPaths += [string]$digistarScriptPlan.OffScriptPath
		}

		[void]$batchItems.Add([pscustomobject]@{
			SourcePath = $sourcePath
			RelativeSourcePath = $relativeSourcePath
			RequestedOutputPath = $requestedOutputPath
			OutputPath = $resolvedOutputPath
			OutputDirectory = $itemOutputDirectory
			DigistarScriptPlan = $digistarScriptPlan
		})
	}

	return [pscustomobject]@{
		InputFolderPath = $absoluteInputFolderPath
		OutputFolderPath = $absoluteOutputFolderPath
		Recursive = $Recursive
		TargetObjectName = $targetSettings.targetObjectName
		TargetRadiusKmText = $normalizedTargetRadiusKmText
		SourceRadiusKmText = $normalizedSourceRadiusKmText
		AnchorLatitudeText = $normalizedAnchorLatitudeText
		AnchorLongitudeText = $normalizedAnchorLongitudeText
		IncludeTargetRadiusSuffix = $IncludeTargetRadiusSuffix
		IncludeAnchorSuffix = $IncludeAnchorSuffix
		CreateDigistarScripts = $CreateDigistarScripts
		Items = @($batchItems)
		ExistingOutputPaths = @($existingOutputPaths)
	}
}

function Invoke-KmlConvertGuiBatchConversion {
	param(
		[pscustomobject]$BatchPlan,
		[string]$NodeCommandPath,
		[string]$DigistarTemplateDirectory,
		[bool]$AllowOverwrite
	)

	if ($null -eq $BatchPlan) {
		throw 'Folder batch conversion requires a batch plan.'
	}

	if ($null -eq $BatchPlan.Items -or $BatchPlan.Items.Count -eq 0) {
		throw 'No eligible .kml files were found in the input folder.'
	}

	$requiredNodeCommandPath = Convert-KmlConvertGuiRequiredText `
		-ValueText $NodeCommandPath `
		-ValueLabel 'Node.js command path'
	$itemResults = New-Object System.Collections.ArrayList
	$convertedCount = 0
	$failedCount = 0
	$skippedCount = 0
	$index = 0

	for ($index = 0; $index -lt $BatchPlan.Items.Count; $index += 1) {
		$batchItem = $BatchPlan.Items[$index]
		$outputExistedAtPreflight = $false
		$itemResult = [ordered]@{
			SourcePath = [string]$batchItem.SourcePath
			OutputPath = [string]$batchItem.OutputPath
			Status = 'failed'
			Message = ''
			OnScriptPath = ''
			OffScriptPath = ''
			ObjectNameStem = ''
		}

		foreach ($existingOutputPath in @($BatchPlan.ExistingOutputPaths)) {
			if (
				[string]::Equals(
					[System.IO.Path]::GetFullPath([string]$batchItem.OutputPath),
					[System.IO.Path]::GetFullPath([string]$existingOutputPath),
					[System.StringComparison]::OrdinalIgnoreCase
				)
			) {
				$outputExistedAtPreflight = $true
				break
			}
		}

		if (
			(Test-Path -LiteralPath $batchItem.OutputPath) -and
			(-not $AllowOverwrite -or -not $outputExistedAtPreflight)
		) {
			$itemResult.Status = 'skipped'
			$itemResult.Message = 'Output already exists and this path was not approved for overwrite.'
			$skippedCount += 1
			[void]$itemResults.Add([pscustomobject]$itemResult)
			continue
		}

		try {
			if (-not (Test-Path -LiteralPath $batchItem.OutputDirectory -PathType Container)) {
				[void][System.IO.Directory]::CreateDirectory([string]$batchItem.OutputDirectory)
			}

			$cliArguments = New-KmlConvertGuiCliArguments `
				-InputPath $batchItem.SourcePath `
				-OutputPath $batchItem.RequestedOutputPath `
				-TargetObjectName $BatchPlan.TargetObjectName `
				-TargetRadiusKmText $BatchPlan.TargetRadiusKmText `
				-SourceRadiusKmText $BatchPlan.SourceRadiusKmText `
				-AnchorLatitudeText $BatchPlan.AnchorLatitudeText `
				-AnchorLongitudeText $BatchPlan.AnchorLongitudeText `
				-IncludeTargetRadiusSuffix $BatchPlan.IncludeTargetRadiusSuffix `
				-IncludeAnchorSuffix $BatchPlan.IncludeAnchorSuffix
			$processResult = Invoke-KmlConvertGuiCliProcess `
				-NodeCommandPath $requiredNodeCommandPath `
				-CliArguments $cliArguments

			if ($processResult.ExitCode -ne 0) {
				$failureText = $processResult.StandardError.Trim()

				if ($failureText -eq '') {
					$failureText = $processResult.StandardOutput.Trim()
				}

				if ($failureText -eq '') {
					$failureText = 'Node process exited with code ' + $processResult.ExitCode + '.'
				}

				throw $failureText
			}

			if (-not (Test-Path -LiteralPath $batchItem.OutputPath -PathType Leaf)) {
				throw 'Converted KML file was not created: ' + $batchItem.OutputPath
			}

			if ($BatchPlan.CreateDigistarScripts) {
				try {
					$templates = Read-KmlConvertGuiDigistarTemplates `
						-TemplateDirectory $DigistarTemplateDirectory
					$scriptContents = New-KmlConvertGuiDigistarScriptContents `
						-ScriptPlan $batchItem.DigistarScriptPlan `
						-Templates $templates
					$digistarResult = Write-KmlConvertGuiDigistarScripts `
						-ScriptPlan $batchItem.DigistarScriptPlan `
						-ScriptContents $scriptContents
					$itemResult.OnScriptPath = [string]$digistarResult.OnScriptPath
					$itemResult.OffScriptPath = [string]$digistarResult.OffScriptPath
					$itemResult.ObjectNameStem = [string]$digistarResult.ObjectNameStem
				} catch {
					throw 'Digistar script generation failed after KML conversion: ' + $_.Exception.Message
				}
			}

			$itemResult.Status = 'converted'
			$itemResult.Message = 'Conversion completed.'
			$convertedCount += 1
		} catch {
			$itemResult.Status = 'failed'
			$itemResult.Message = $_.Exception.Message
			$failedCount += 1
		}

		[void]$itemResults.Add([pscustomobject]$itemResult)
	}

	return [pscustomobject]@{
		ConvertedCount = $convertedCount
		FailedCount = $failedCount
		SkippedCount = $skippedCount
		OverallSuccess = ($failedCount -eq 0)
		Items = @($itemResults)
	}
}

function New-KmlConvertGuiCliArguments {
	param(
		[string]$InputPath,
		[string]$OutputPath,
		[string]$TargetObjectName,
		[string]$TargetRadiusKmText,
		[string]$SourceRadiusKmText,
		[string]$AnchorLatitudeText,
		[string]$AnchorLongitudeText,
		[bool]$IncludeTargetRadiusSuffix,
		[bool]$IncludeAnchorSuffix
	)

	$trimmedInputPath = ''
	$resolvedOutputPath = ''
	$outputDirectory = ''
	$targetSettings = $null
	$sourceRadiusKm = $null
	$anchorValues = $null
	$cliArguments = @()

	if ($null -ne $InputPath) {
		$trimmedInputPath = $InputPath.Trim()
	}

	if ($trimmedInputPath -eq '') {
		throw 'Input KML path is required.'
	}

	if (-not (Test-Path -LiteralPath $trimmedInputPath -PathType Leaf)) {
		throw 'Input KML file not found: ' + $trimmedInputPath
	}

	if ([System.IO.Path]::GetExtension($trimmedInputPath).ToLowerInvariant() -ne '.kml') {
		throw 'Input file must use the .kml extension.'
	}

	$targetSettings = Resolve-KmlConvertGuiTargetSettings `
		-TargetObjectName $TargetObjectName `
		-TargetRadiusKmText $TargetRadiusKmText
	$resolvedOutputPath = Resolve-KmlConvertGuiOutputPath `
		-RequestedOutputPath $OutputPath `
		-TargetObjectName $TargetObjectName `
		-TargetRadiusKmText $TargetRadiusKmText `
		-IncludeTargetRadiusSuffix $IncludeTargetRadiusSuffix `
		-AnchorLatitudeText $AnchorLatitudeText `
		-AnchorLongitudeText $AnchorLongitudeText `
		-IncludeAnchorSuffix $IncludeAnchorSuffix
	$outputDirectory = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($resolvedOutputPath))

	if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
		throw 'Output folder not found: ' + $outputDirectory
	}

	if (
		[System.IO.Path]::GetFullPath($trimmedInputPath).Equals(
			[System.IO.Path]::GetFullPath($resolvedOutputPath),
			[System.StringComparison]::OrdinalIgnoreCase
		)
	) {
		throw 'Output KML path must differ from the input KML path.'
	}

	$sourceRadiusKm = Convert-KmlConvertGuiNumberText -ValueText $SourceRadiusKmText -FieldLabel 'Source radius'

	if ($null -ne $sourceRadiusKm -and $sourceRadiusKm -le 0) {
		throw 'Source radius must be greater than zero.'
	}

	$anchorValues = Resolve-KmlConvertGuiAnchorTextValues `
		-AnchorLatitudeText $AnchorLatitudeText `
		-AnchorLongitudeText $AnchorLongitudeText

	$cliArguments += Get-KmlConvertGuiCliScriptPath
	$cliArguments += '--input'
	$cliArguments += $trimmedInputPath
	$cliArguments += '--output'
	$cliArguments += $resolvedOutputPath
	$cliArguments += '--target-radius'
	$cliArguments += $targetSettings.targetRadiusMetersText

	if ($null -ne $sourceRadiusKm) {
		$cliArguments += '--source-radius'
		$cliArguments += Convert-KmlConvertGuiKilometersToMetersText -Kilometers $sourceRadiusKm
	}

	if ($null -ne $anchorValues) {
		$cliArguments += '--anchor'
		$cliArguments += (
			$anchorValues.Latitude.ToString('0.###############', [System.Globalization.CultureInfo]::InvariantCulture) +
			',' +
			$anchorValues.Longitude.ToString('0.###############', [System.Globalization.CultureInfo]::InvariantCulture)
		)
	}

	return ,$cliArguments
}

function Convert-KmlConvertGuiArgumentToCommandLineText {
	param(
		[string]$ArgumentText
	)

	$escapedArgumentText = ''

	if ($null -eq $ArgumentText -or $ArgumentText -eq '') {
		return '""'
	}

	if ($ArgumentText -notmatch '[\s"]') {
		return $ArgumentText
	}

	$escapedArgumentText = $ArgumentText -replace '(\\*)"', '$1$1\"'
	$escapedArgumentText = $escapedArgumentText -replace '(\\+)$', '$1$1'

	return '"' + $escapedArgumentText + '"'
}

function Convert-KmlConvertGuiArgumentListToCommandLineText {
	param(
		[string[]]$ArgumentList
	)

	$quotedArguments = @()
	$index = 0

	for ($index = 0; $index -lt $ArgumentList.Length; $index += 1) {
		$quotedArguments += Convert-KmlConvertGuiArgumentToCommandLineText -ArgumentText $ArgumentList[$index]
	}

	return ($quotedArguments -join ' ')
}

function Invoke-KmlConvertGuiCliProcess {
	param(
		[string]$NodeCommandPath,
		[string[]]$CliArguments
	)

	$processInfo = New-Object System.Diagnostics.ProcessStartInfo
	$process = $null
	$standardOutputTask = $null
	$standardErrorTask = $null
	$standardOutput = ''
	$standardError = ''
	$index = 0

	$processInfo.FileName = $NodeCommandPath
	$processInfo.WorkingDirectory = $PSScriptRoot
	$processInfo.UseShellExecute = $false
	$processInfo.RedirectStandardOutput = $true
	$processInfo.RedirectStandardError = $true
	$processInfo.CreateNoWindow = $true

	if ($processInfo.PSObject.Properties.Name -contains 'ArgumentList') {
		for ($index = 0; $index -lt $CliArguments.Length; $index += 1) {
			$null = $processInfo.ArgumentList.Add($CliArguments[$index])
		}
	} else {
		$processInfo.Arguments = Convert-KmlConvertGuiArgumentListToCommandLineText -ArgumentList $CliArguments
	}

	$process = [System.Diagnostics.Process]::Start($processInfo)

	if ($null -eq $process) {
		throw 'Failed to start the Node.js conversion process.'
	}

	try {
		$standardOutputTask = $process.StandardOutput.ReadToEndAsync()
		$standardErrorTask = $process.StandardError.ReadToEndAsync()

		while (-not $process.HasExited) {
			[System.Windows.Forms.Application]::DoEvents()
			Start-Sleep -Milliseconds 30
		}

		$process.WaitForExit()
		$standardOutput = $standardOutputTask.Result
		$standardError = $standardErrorTask.Result

		return [pscustomobject]@{
			ExitCode = $process.ExitCode
			StandardOutput = $standardOutput
			StandardError = $standardError
		}
	} finally {
		$process.Dispose()
	}
}

function Add-KmlConvertGuiLogText {
	param(
		[System.Windows.Forms.TextBox]$LogTextBox,
		[string]$TextToAppend
	)

	$normalizedText = ''

	if ($null -ne $TextToAppend) {
		$normalizedText = $TextToAppend.Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", [System.Environment]::NewLine)
	}

	if ($LogTextBox.TextLength -gt 0) {
		$LogTextBox.AppendText([System.Environment]::NewLine)
	}

	$LogTextBox.AppendText($normalizedText)
	$LogTextBox.SelectionStart = $LogTextBox.TextLength
	$LogTextBox.ScrollToCaret()
}

function New-KmlConvertGuiAnchorMapFormParts {
	param(
		[string]$TargetObjectName,
		[System.Windows.Forms.TextBox]$AnchorLatitudeTextBox,
		[System.Windows.Forms.TextBox]$AnchorLongitudeTextBox,
		[string]$MapCatalogPath
	)

	if ($null -eq $AnchorLatitudeTextBox -or $null -eq $AnchorLongitudeTextBox) {
		throw 'Anchor latitude and longitude text boxes are required.'
	}

	$targetObject = Get-KmlConvertGuiTargetObjectDefinition -TargetObjectName $TargetObjectName
	$mapImage = Get-KmlConvertGuiTargetMapImage `
		-TargetObjectName $TargetObjectName `
		-MapCatalogPath $MapCatalogPath
	$mapForm = New-Object System.Windows.Forms.Form
	$mainLayout = New-Object System.Windows.Forms.TableLayoutPanel
	$targetLabel = New-Object System.Windows.Forms.Label
	$mapCanvas = New-Object System.Windows.Forms.PictureBox
	$anchorReadoutLabel = New-Object System.Windows.Forms.Label
	$buttonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
	$clearAnchorButton = New-Object System.Windows.Forms.Button
	$closeMapButton = New-Object System.Windows.Forms.Button
	$mapSourceLabel = New-Object System.Windows.Forms.Label
	$mapState = [pscustomobject]@{
		MarkerPoint = $null
		DisplayRectangle = $null
		IsUpdatingAnchorFields = $false
	}

	$mapForm.Text = 'Choose anchor on ' + $targetObject.name
	$mapForm.StartPosition = 'CenterParent'
	$mapForm.Size = New-Object System.Drawing.Size(1000, 700)
	$mapForm.MinimumSize = New-Object System.Drawing.Size(640, 480)
	$mapForm.SizeGripStyle = 'Show'

	$mainLayout.Dock = 'Fill'
	$mainLayout.Padding = New-Object System.Windows.Forms.Padding(12)
	$mainLayout.ColumnCount = 1
	$mainLayout.RowCount = 5
	[void]$mainLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
	[void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
	[void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
	[void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
	[void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
	[void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))

	$targetLabel.AutoSize = $true
	$targetLabel.Text = $targetObject.name + ': click inside the map to set the anchor.'
	$targetLabel.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)

	$mapCanvas.Dock = 'Fill'
	$mapCanvas.BackColor = [System.Drawing.Color]::DimGray
	$mapCanvas.BorderStyle = 'FixedSingle'
	$mapCanvas.Cursor = [System.Windows.Forms.Cursors]::Cross
	$mapCanvas.MinimumSize = New-Object System.Drawing.Size(400, 200)

	$anchorReadoutLabel.AutoSize = $true
	$anchorReadoutLabel.Text = 'Anchor: not set.'
	$anchorReadoutLabel.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 4)

	$buttonPanel.AutoSize = $true
	$buttonPanel.FlowDirection = 'LeftToRight'
	$buttonPanel.WrapContents = $false
	$buttonPanel.Margin = New-Object System.Windows.Forms.Padding(0)
	$clearAnchorButton.Text = 'Clear anchor'
	$clearAnchorButton.AutoSize = $true
	$closeMapButton.Text = 'Close map'
	$closeMapButton.AutoSize = $true
	[void]$buttonPanel.Controls.Add($clearAnchorButton)
	[void]$buttonPanel.Controls.Add($closeMapButton)

	$mapSourceLabel.AutoSize = $true
	$mapSourceLabel.Text = $mapImage.Message
	$mapSourceLabel.ForeColor = [System.Drawing.Color]::DimGray
	$mapSourceLabel.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)

	[void]$mainLayout.Controls.Add($targetLabel, 0, 0)
	[void]$mainLayout.Controls.Add($mapCanvas, 0, 1)
	[void]$mainLayout.Controls.Add($anchorReadoutLabel, 0, 2)
	[void]$mainLayout.Controls.Add($buttonPanel, 0, 3)
	[void]$mainLayout.Controls.Add($mapSourceLabel, 0, 4)
	[void]$mapForm.Controls.Add($mainLayout)
	$mapForm.AcceptButton = $closeMapButton

	$getDisplayRectangleAction = ${function:Get-KmlConvertGuiMapDisplayRectangle}
	$convertPointToAnchorAction = ${function:Convert-KmlConvertGuiMapPointToAnchor}
	$convertAnchorToPointAction = ${function:Convert-KmlConvertGuiAnchorToMapPoint}
	$convertCoordinateTextAction = ${function:Convert-KmlConvertGuiCoordinateToText}
	$resolveAnchorTextAction = ${function:Resolve-KmlConvertGuiAnchorTextValues}

	$getCurrentDisplayRectangle = {
		if ($mapCanvas.ClientSize.Width -le 0 -or $mapCanvas.ClientSize.Height -le 0) {
			return $null
		}

		return & $getDisplayRectangleAction `
			-ViewportWidth $mapCanvas.ClientSize.Width `
			-ViewportHeight $mapCanvas.ClientSize.Height `
			-ImageWidth $mapImage.Bitmap.Width `
			-ImageHeight $mapImage.Bitmap.Height
	}.GetNewClosure()

	$syncMapFromAnchorFields = {
		$anchorValues = $null
		$displayRectangle = & $getCurrentDisplayRectangle

		try {
			$anchorValues = & $resolveAnchorTextAction `
				-AnchorLatitudeText $AnchorLatitudeTextBox.Text `
				-AnchorLongitudeText $AnchorLongitudeTextBox.Text
		} catch {
			$mapState.MarkerPoint = $null
			$anchorReadoutLabel.Text = 'Anchor: enter a valid latitude and longitude pair.'
			$mapCanvas.Invalidate()
			return
		}

		if ($null -eq $anchorValues) {
			$mapState.MarkerPoint = $null
			$anchorReadoutLabel.Text = 'Anchor: not set.'
			$mapCanvas.Invalidate()
			return
		}

		$anchorReadoutLabel.Text = (
			'Anchor: latitude ' +
			(& $convertCoordinateTextAction -Coordinate $anchorValues.Latitude) +
			', longitude ' +
			(& $convertCoordinateTextAction -Coordinate $anchorValues.Longitude)
		)

		if ($null -ne $displayRectangle) {
			$mapState.MarkerPoint = & $convertAnchorToPointAction `
				-Latitude $anchorValues.Latitude `
				-Longitude $anchorValues.Longitude `
				-DisplayRectangle $displayRectangle
		} else {
			$mapState.MarkerPoint = $null
		}

		$mapCanvas.Invalidate()
	}.GetNewClosure()

	$applyMapPointToAnchorFields = {
		param(
			[double]$PointX,
			[double]$PointY
		)

		$displayRectangle = & $getCurrentDisplayRectangle

		if ($null -eq $displayRectangle) {
			return $false
		}

		$anchorValues = & $convertPointToAnchorAction `
			-PointX $PointX `
			-PointY $PointY `
			-DisplayRectangle $displayRectangle

		if ($null -eq $anchorValues) {
			return $false
		}

		$mapState.IsUpdatingAnchorFields = $true
		$AnchorLatitudeTextBox.Text = & $convertCoordinateTextAction -Coordinate $anchorValues.Latitude
		$AnchorLongitudeTextBox.Text = & $convertCoordinateTextAction -Coordinate $anchorValues.Longitude
		$mapState.IsUpdatingAnchorFields = $false
		& $syncMapFromAnchorFields
		return $true
	}.GetNewClosure()

	$clearAnchorAction = {
		$mapState.IsUpdatingAnchorFields = $true
		$AnchorLatitudeTextBox.Clear()
		$AnchorLongitudeTextBox.Clear()
		$mapState.IsUpdatingAnchorFields = $false
		& $syncMapFromAnchorFields
	}.GetNewClosure()

	$anchorFieldsChangedHandler = {
		if (-not $mapState.IsUpdatingAnchorFields) {
			& $syncMapFromAnchorFields
		}
	}.GetNewClosure()

	$mapCanvas.Add_Paint({
		param($sender, $eventArgs)

		$displayRectangle = & $getCurrentDisplayRectangle

		if ($null -eq $displayRectangle) {
			return
		}

		$mapState.DisplayRectangle = $displayRectangle
		$eventArgs.Graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
		$eventArgs.Graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
		$eventArgs.Graphics.DrawImage($mapImage.Bitmap, $displayRectangle)
		$borderPen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 1)

		try {
			$eventArgs.Graphics.DrawRectangle(
				$borderPen,
				$displayRectangle.X,
				$displayRectangle.Y,
				$displayRectangle.Width - 1,
				$displayRectangle.Height - 1
			)
		} finally {
			$borderPen.Dispose()
		}

		if ($null -ne $mapState.MarkerPoint) {
			$outlinePen = New-Object System.Drawing.Pen([System.Drawing.Color]::Black, 5)
			$markerPen = New-Object System.Drawing.Pen([System.Drawing.Color]::Yellow, 2)
			$markerX = [single]$mapState.MarkerPoint.X
			$markerY = [single]$mapState.MarkerPoint.Y
			$markerRadius = 12

			try {
				foreach ($pen in @($outlinePen, $markerPen)) {
					$eventArgs.Graphics.DrawLine($pen, $markerX - $markerRadius, $markerY, $markerX + $markerRadius, $markerY)
					$eventArgs.Graphics.DrawLine($pen, $markerX, $markerY - $markerRadius, $markerX, $markerY + $markerRadius)
					$eventArgs.Graphics.DrawEllipse($pen, $markerX - 5, $markerY - 5, 10, 10)
				}
			} finally {
				$markerPen.Dispose()
				$outlinePen.Dispose()
			}
		}
	}.GetNewClosure())

	$mapCanvas.Add_MouseClick({
		param($sender, $eventArgs)

		[void](& $applyMapPointToAnchorFields -PointX $eventArgs.X -PointY $eventArgs.Y)
	}.GetNewClosure())

	$mapCanvas.Add_Resize({
		& $syncMapFromAnchorFields
	}.GetNewClosure())

	$AnchorLatitudeTextBox.Add_TextChanged($anchorFieldsChangedHandler)
	$AnchorLongitudeTextBox.Add_TextChanged($anchorFieldsChangedHandler)

	$clearAnchorButton.Add_Click({
		& $clearAnchorAction
	}.GetNewClosure())

	$closeMapButton.Add_Click({
		$mapForm.Close()
	}.GetNewClosure())

	$mapForm.Add_Shown({
		& $syncMapFromAnchorFields
	}.GetNewClosure())

	$mapForm.Add_Disposed({
		$AnchorLatitudeTextBox.Remove_TextChanged($anchorFieldsChangedHandler)
		$AnchorLongitudeTextBox.Remove_TextChanged($anchorFieldsChangedHandler)
		$mapImage.Bitmap.Dispose()
	}.GetNewClosure())

	& $syncMapFromAnchorFields

	return [pscustomobject]@{
		Form = $mapForm
		MapCanvas = $mapCanvas
		MapImage = $mapImage
		MapState = $mapState
		AnchorReadoutLabel = $anchorReadoutLabel
		MapSourceLabel = $mapSourceLabel
		ClearAnchorButton = $clearAnchorButton
		CloseMapButton = $closeMapButton
		ApplyMapPointAction = $applyMapPointToAnchorFields
		SyncMapFromAnchorFieldsAction = $syncMapFromAnchorFields
	}
}

function Set-KmlConvertGuiSplitterDistance {
	param(
		[System.Windows.Forms.SplitContainer]$SplitContainer,
		[int]$RequestedDistance
	)

	$minimumDistance = $SplitContainer.Panel1MinSize
	$maximumDistance = $SplitContainer.Height - $SplitContainer.Panel2MinSize - $SplitContainer.SplitterWidth
	$resolvedDistance = $RequestedDistance

	if ($maximumDistance -le $minimumDistance) {
		return
	}

	if ($resolvedDistance -lt $minimumDistance) {
		$resolvedDistance = $minimumDistance
	}

	if ($resolvedDistance -gt $maximumDistance) {
		$resolvedDistance = $maximumDistance
	}

	$SplitContainer.SplitterDistance = $resolvedDistance
}

function New-KmlConvertGuiFormParts {
	param(
		[string]$LayoutSettingsPath,
		[string]$DigistarTemplateDirectory
	)

	$form = New-Object System.Windows.Forms.Form
	$toolTip = New-Object System.Windows.Forms.ToolTip
	$menuStrip = New-Object System.Windows.Forms.MenuStrip
	$fileMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
	$helpMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
	$inputFileMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
	$documentationMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
	$quitMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
	$fontSizeSpacerLabel = New-Object System.Windows.Forms.ToolStripLabel
	$fontSizeLabel = New-Object System.Windows.Forms.ToolStripLabel
	$decreaseFontButton = New-Object System.Windows.Forms.ToolStripButton
	$fontSizeValueLabel = New-Object System.Windows.Forms.ToolStripLabel
	$increaseFontButton = New-Object System.Windows.Forms.ToolStripButton
	$mainLayout = New-Object System.Windows.Forms.TableLayoutPanel
	$headerLayout = New-Object System.Windows.Forms.TableLayoutPanel
	$statusPanel = New-Object System.Windows.Forms.Panel
	$statusLabel = New-Object System.Windows.Forms.Label
	$pathSettingsSplitContainer = New-Object System.Windows.Forms.SplitContainer
	$settingsFileNameSplitContainer = New-Object System.Windows.Forms.SplitContainer
	$fileNameRunLogSplitContainer = New-Object System.Windows.Forms.SplitContainer
	$pathGroupBox = New-Object System.Windows.Forms.GroupBox
	$pathLayout = New-Object System.Windows.Forms.TableLayoutPanel
	$modePanel = New-Object System.Windows.Forms.FlowLayoutPanel
	$singleFileModeRadioButton = New-Object System.Windows.Forms.RadioButton
	$folderModeRadioButton = New-Object System.Windows.Forms.RadioButton
	$inputPathLabel = New-Object System.Windows.Forms.Label
	$inputPathTextBox = New-Object System.Windows.Forms.TextBox
	$inputBrowseButton = New-Object System.Windows.Forms.Button
	$outputPathLabel = New-Object System.Windows.Forms.Label
	$outputPathTextBox = New-Object System.Windows.Forms.TextBox
	$outputBrowseButton = New-Object System.Windows.Forms.Button
	$recursiveCheckBox = New-Object System.Windows.Forms.CheckBox
	$optionsGroupBox = New-Object System.Windows.Forms.GroupBox
	$optionsLayout = New-Object System.Windows.Forms.TableLayoutPanel
	$targetObjectLabel = New-Object System.Windows.Forms.Label
	$targetObjectComboBox = New-Object System.Windows.Forms.ComboBox
	$targetRadiusLabel = New-Object System.Windows.Forms.Label
	$targetRadiusTextBox = New-Object System.Windows.Forms.TextBox
	$sourceRadiusLabel = New-Object System.Windows.Forms.Label
	$sourceRadiusTextBox = New-Object System.Windows.Forms.TextBox
	$anchorLatitudeLabel = New-Object System.Windows.Forms.Label
	$anchorLatitudeTextBox = New-Object System.Windows.Forms.TextBox
	$anchorLongitudeLabel = New-Object System.Windows.Forms.Label
	$anchorLongitudeTextBox = New-Object System.Windows.Forms.TextBox
	$anchorActionPanel = New-Object System.Windows.Forms.FlowLayoutPanel
	$chooseAnchorMapButton = New-Object System.Windows.Forms.Button
	$clearAnchorButton = New-Object System.Windows.Forms.Button
	$createDigistarScriptsCheckBox = New-Object System.Windows.Forms.CheckBox
	$fileNameGroupBox = New-Object System.Windows.Forms.GroupBox
	$fileNameLayout = New-Object System.Windows.Forms.TableLayoutPanel
	$fileNamePreviewLabel = New-Object System.Windows.Forms.Label
	$fileNamePreviewDetailLabel = New-Object System.Windows.Forms.Label
	$fileNameInfoLabel = New-Object System.Windows.Forms.Label
	$fileNameOptionsPanel = New-Object System.Windows.Forms.FlowLayoutPanel
	$fileNamePresetLabel = New-Object System.Windows.Forms.Label
	$presetNoneRadioButton = New-Object System.Windows.Forms.RadioButton
	$presetAllRadioButton = New-Object System.Windows.Forms.RadioButton
	$targetRadiusSuffixCheckBox = New-Object System.Windows.Forms.CheckBox
	$anchorSuffixCheckBox = New-Object System.Windows.Forms.CheckBox
	$processButton = New-Object System.Windows.Forms.Button
	$logGroupBox = New-Object System.Windows.Forms.GroupBox
	$logTextBox = New-Object System.Windows.Forms.TextBox
	$inputFileDialog = New-Object System.Windows.Forms.OpenFileDialog
	$outputFileDialog = New-Object System.Windows.Forms.SaveFileDialog
	$inputFolderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
	$outputFolderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
	$formState = [pscustomobject]@{
		IsRunning = $false
		IsUpdatingOutputPath = $false
		IsOutputPathAutoManaged = $true
		IsUpdatingSuffixControls = $false
		BaseFontSize = 10.0
		MinimumFontSize = 8.0
		MaximumFontSize = 18.0
		OwnedFonts = New-Object System.Collections.ArrayList
	}
	$targetObjectNames = @()
	$index = 0
	$currentTargetObject = $null
	$documentationFolderPath = Join-Path $PSScriptRoot 'docs'

	if ($null -eq $LayoutSettingsPath -or $LayoutSettingsPath.Trim() -eq '') {
		$LayoutSettingsPath = Join-Path $PSScriptRoot 'layoutSettings.json'
	}

	$form.Text = 'Interplanetary Boundaries KML Converter'
	$form.StartPosition = 'CenterScreen'
	$form.Size = New-Object System.Drawing.Size(1120, 950)
	$form.MinimumSize = New-Object System.Drawing.Size(900, 900)
	$initialFormFont = New-Object System.Drawing.Font('Segoe UI', $formState.BaseFontSize)
	$initialStatusFont = New-Object System.Drawing.Font($initialFormFont.FontFamily, ($initialFormFont.Size + 1), [System.Drawing.FontStyle]::Bold)
	[void]$formState.OwnedFonts.Add($initialFormFont)
	[void]$formState.OwnedFonts.Add($initialStatusFont)
	$form.Font = $initialFormFont

	$toolTip.ShowAlways = $true

	$fileMenuItem.Text = 'File'
	$helpMenuItem.Text = 'Help'
	$inputFileMenuItem.Text = 'Input File...'
	$documentationMenuItem.Text = 'Documentation'
	$quitMenuItem.Text = 'Quit'
	[void]$fileMenuItem.DropDownItems.Add($inputFileMenuItem)
	[void]$fileMenuItem.DropDownItems.Add($quitMenuItem)
	[void]$helpMenuItem.DropDownItems.Add($documentationMenuItem)
	[void]$menuStrip.Items.Add($fileMenuItem)
	[void]$menuStrip.Items.Add($helpMenuItem)
	$fontSizeSpacerLabel.AutoSize = $false
	$fontSizeSpacerLabel.Size = New-Object System.Drawing.Size(24, 20)
	$fontSizeLabel.Text = 'Font size'
	$fontSizeLabel.Margin = New-Object System.Windows.Forms.Padding(0, 1, 4, 2)
	$decreaseFontButton.Text = '-'
	$decreaseFontButton.AutoSize = $false
	$decreaseFontButton.Size = New-Object System.Drawing.Size(24, 22)
	$decreaseFontButton.Margin = New-Object System.Windows.Forms.Padding(0, 0, 2, 0)
	$fontSizeValueLabel.AutoSize = $false
	$fontSizeValueLabel.Size = New-Object System.Drawing.Size(30, 22)
	$fontSizeValueLabel.TextAlign = 'MiddleCenter'
	$fontSizeValueLabel.Margin = New-Object System.Windows.Forms.Padding(0)
	$increaseFontButton.Text = '+'
	$increaseFontButton.AutoSize = $false
	$increaseFontButton.Size = New-Object System.Drawing.Size(24, 22)
	$increaseFontButton.Margin = New-Object System.Windows.Forms.Padding(2, 0, 0, 0)
	[void]$menuStrip.Items.Add($fontSizeSpacerLabel)
	[void]$menuStrip.Items.Add($fontSizeLabel)
	[void]$menuStrip.Items.Add($decreaseFontButton)
	[void]$menuStrip.Items.Add($fontSizeValueLabel)
	[void]$menuStrip.Items.Add($increaseFontButton)
	$form.MainMenuStrip = $menuStrip

	$mainLayout.Dock = 'Fill'
	$mainLayout.Padding = New-Object System.Windows.Forms.Padding(14)
	$mainLayout.ColumnCount = 1
	$mainLayout.RowCount = 2
	[void]$mainLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
	[void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
	[void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))

	$headerLayout.AutoSize = $true
	$headerLayout.Dock = 'Fill'
	$headerLayout.ColumnCount = 2
	$headerLayout.RowCount = 1
	[void]$headerLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
	[void]$headerLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))

	$statusPanel.Dock = 'Fill'
	$statusPanel.BorderStyle = 'FixedSingle'
	$statusPanel.Padding = New-Object System.Windows.Forms.Padding(10, 6, 10, 6)
	$statusPanel.Margin = New-Object System.Windows.Forms.Padding(0, 0, 12, 10)
	$statusPanel.MinimumSize = New-Object System.Drawing.Size(0, 48)
	$statusLabel.Dock = 'Fill'
	$statusLabel.TextAlign = 'MiddleLeft'
	$statusLabel.Font = $initialStatusFont
	[void]$statusPanel.Controls.Add($statusLabel)

	$processButton.Text = 'Convert File'
	$processButton.MinimumSize = New-Object System.Drawing.Size(150, 38)
	$processButton.Margin = New-Object System.Windows.Forms.Padding(0, 5, 0, 10)
	[void]$headerLayout.Controls.Add($statusPanel, 0, 0)
	[void]$headerLayout.Controls.Add($processButton, 1, 0)

	foreach ($splitContainer in @(
		$pathSettingsSplitContainer,
		$settingsFileNameSplitContainer,
		$fileNameRunLogSplitContainer
	)) {
		$splitContainer.Dock = 'Fill'
		$splitContainer.Orientation = 'Horizontal'
		$splitContainer.SplitterWidth = 6
		$splitContainer.Panel1MinSize = 60
		$splitContainer.Panel2MinSize = 60
		$splitContainer.BorderStyle = 'None'
	}

	$pathSettingsSplitContainer.Panel1MinSize = 180

	$pathGroupBox.Dock = 'Fill'
	$pathGroupBox.Text = 'Input and output paths'
	$pathGroupBox.Padding = New-Object System.Windows.Forms.Padding(12, 24, 12, 12)
	$pathLayout.Dock = 'Fill'
	$pathLayout.ColumnCount = 2
	$pathLayout.RowCount = 6
	[void]$pathLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
	[void]$pathLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
	$modePanel.AutoSize = $true
	$modePanel.FlowDirection = 'LeftToRight'
	$modePanel.WrapContents = $false
	$modePanel.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
	$singleFileModeRadioButton.Text = 'Single file'
	$singleFileModeRadioButton.AutoSize = $true
	$singleFileModeRadioButton.Checked = $true
	$folderModeRadioButton.Text = 'Folder batch'
	$folderModeRadioButton.AutoSize = $true
	[void]$modePanel.Controls.Add($singleFileModeRadioButton)
	[void]$modePanel.Controls.Add($folderModeRadioButton)
	$inputPathLabel.Text = 'Input KML file'
	$inputPathLabel.AutoSize = $true
	$inputPathTextBox.Dock = 'Fill'
	$inputBrowseButton.Text = 'Browse...'
	$inputBrowseButton.AutoSize = $true
	$outputPathLabel.Text = 'Output KML save path (chosen stem)'
	$outputPathLabel.AutoSize = $true
	$outputPathTextBox.Dock = 'Fill'
	$outputBrowseButton.Text = 'Browse...'
	$outputBrowseButton.AutoSize = $true
	$recursiveCheckBox.Text = 'Include subfolders and preserve the input folder tree'
	$recursiveCheckBox.AutoSize = $true
	$recursiveCheckBox.Visible = $false
	$recursiveCheckBox.Enabled = $false
	[void]$pathLayout.Controls.Add($modePanel, 0, 0)
	$pathLayout.SetColumnSpan($modePanel, 2)
	[void]$pathLayout.Controls.Add($inputPathLabel, 0, 1)
	$pathLayout.SetColumnSpan($inputPathLabel, 2)
	[void]$pathLayout.Controls.Add($inputPathTextBox, 0, 2)
	[void]$pathLayout.Controls.Add($inputBrowseButton, 1, 2)
	[void]$pathLayout.Controls.Add($outputPathLabel, 0, 3)
	$pathLayout.SetColumnSpan($outputPathLabel, 2)
	[void]$pathLayout.Controls.Add($outputPathTextBox, 0, 4)
	[void]$pathLayout.Controls.Add($outputBrowseButton, 1, 4)
	[void]$pathLayout.Controls.Add($recursiveCheckBox, 0, 5)
	$pathLayout.SetColumnSpan($recursiveCheckBox, 2)
	[void]$pathGroupBox.Controls.Add($pathLayout)
	$toolTip.SetToolTip($singleFileModeRadioButton, 'Convert one selected KML file.')
	$toolTip.SetToolTip($folderModeRadioButton, 'Convert every eligible KML file in a selected folder.')
	$toolTip.SetToolTip($recursiveCheckBox, 'Include subfolders and recreate their relative tree under the output folder.')

	$optionsGroupBox.Dock = 'Fill'
	$optionsGroupBox.Text = 'Great-circle conversion settings'
	$optionsGroupBox.Padding = New-Object System.Windows.Forms.Padding(12, 24, 12, 12)
	$optionsLayout.Dock = 'Fill'
	$optionsLayout.AutoScroll = $true
	$optionsLayout.ColumnCount = 4
	$optionsLayout.RowCount = 5
	[void]$optionsLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 25)))
	[void]$optionsLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 25)))
	[void]$optionsLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 25)))
	[void]$optionsLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 25)))

	$targetObjectLabel.Text = 'Target object'
	$targetObjectLabel.AutoSize = $true
	$targetObjectComboBox.Dock = 'Fill'
	$targetObjectComboBox.DropDownStyle = 'DropDownList'

	for ($index = 0; $index -lt $script:kmlConvertGuiConfig.targetObjects.Count; $index += 1) {
		$currentTargetObject = $script:kmlConvertGuiConfig.targetObjects[$index]
		$targetObjectNames += [string]$currentTargetObject.name
	}

	$targetObjectComboBox.Items.AddRange($targetObjectNames)
	$targetObjectComboBox.SelectedItem = $script:kmlConvertGuiConfig.defaultTargetObjectName
	$targetRadiusLabel.Text = 'Custom target radius km'
	$targetRadiusLabel.AutoSize = $true
	$targetRadiusTextBox.Dock = 'Fill'
	$sourceRadiusLabel.Text = 'Custom source radius km (Earth default: ' + $script:kmlConvertGuiConfig.earthMeanRadiusKm + ')'
	$sourceRadiusLabel.AutoSize = $true
	$sourceRadiusTextBox.Dock = 'Fill'
	$anchorLatitudeLabel.Text = 'Anchor latitude (-90 to 90)'
	$anchorLatitudeLabel.AutoSize = $true
	$anchorLatitudeTextBox.Dock = 'Fill'
	$anchorLongitudeLabel.Text = 'Anchor longitude (-180 to 180)'
	$anchorLongitudeLabel.AutoSize = $true
	$anchorLongitudeTextBox.Dock = 'Fill'
	$anchorActionPanel.AutoSize = $true
	$anchorActionPanel.FlowDirection = 'LeftToRight'
	$anchorActionPanel.WrapContents = $false
	$anchorActionPanel.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
	$chooseAnchorMapButton.Text = 'Choose on map...'
	$chooseAnchorMapButton.AutoSize = $true
	$clearAnchorButton.Text = 'Clear anchor'
	$clearAnchorButton.AutoSize = $true
	[void]$anchorActionPanel.Controls.Add($chooseAnchorMapButton)
	[void]$anchorActionPanel.Controls.Add($clearAnchorButton)
	$createDigistarScriptsCheckBox.Text = 'Create Digistar scripts'
	$createDigistarScriptsCheckBox.AutoSize = $true
	$createDigistarScriptsCheckBox.Checked = $false
	$createDigistarScriptsCheckBox.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
	[void]$optionsLayout.Controls.Add($targetObjectLabel, 0, 0)
	[void]$optionsLayout.Controls.Add($targetObjectComboBox, 1, 0)
	[void]$optionsLayout.Controls.Add($targetRadiusLabel, 2, 0)
	[void]$optionsLayout.Controls.Add($targetRadiusTextBox, 3, 0)
	[void]$optionsLayout.Controls.Add($sourceRadiusLabel, 0, 1)
	[void]$optionsLayout.Controls.Add($sourceRadiusTextBox, 1, 1)
	[void]$optionsLayout.Controls.Add($anchorLatitudeLabel, 0, 2)
	[void]$optionsLayout.Controls.Add($anchorLatitudeTextBox, 1, 2)
	[void]$optionsLayout.Controls.Add($anchorLongitudeLabel, 2, 2)
	[void]$optionsLayout.Controls.Add($anchorLongitudeTextBox, 3, 2)
	[void]$optionsLayout.Controls.Add($anchorActionPanel, 0, 3)
	$optionsLayout.SetColumnSpan($anchorActionPanel, 4)
	[void]$optionsLayout.Controls.Add($createDigistarScriptsCheckBox, 0, 4)
	$optionsLayout.SetColumnSpan($createDigistarScriptsCheckBox, 4)
	[void]$optionsGroupBox.Controls.Add($optionsLayout)

	$toolTip.SetToolTip($targetObjectLabel, 'Choose a stored target body. Mars is selected by default.')
	$toolTip.SetToolTip($targetObjectComboBox, 'Choose a stored target body. Mars is selected by default.')
	$toolTip.SetToolTip($targetRadiusLabel, 'Optional radius override in kilometers. A custom value overrides the selected target body.')
	$toolTip.SetToolTip($targetRadiusTextBox, 'Optional radius override in kilometers. A custom value overrides the selected target body.')
	$toolTip.SetToolTip($sourceRadiusLabel, 'Optional source radius in kilometers. Leave blank to let scale-kml.js use its Earth default.')
	$toolTip.SetToolTip($sourceRadiusTextBox, 'Optional source radius in kilometers. Leave blank to let scale-kml.js use its Earth default.')
	$toolTip.SetToolTip($anchorLatitudeLabel, 'Optional target anchor latitude. Latitude and longitude must be supplied together.')
	$toolTip.SetToolTip($anchorLatitudeTextBox, 'Optional target anchor latitude. Latitude and longitude must be supplied together.')
	$toolTip.SetToolTip($anchorLongitudeLabel, 'Optional target anchor longitude. Latitude and longitude must be supplied together.')
	$toolTip.SetToolTip($anchorLongitudeTextBox, 'Optional target anchor longitude. Latitude and longitude must be supplied together.')
	$toolTip.SetToolTip($chooseAnchorMapButton, 'Open a clickable latitude/longitude map for the selected target body.')
	$toolTip.SetToolTip($clearAnchorButton, 'Clear both anchor fields so scale-kml.js uses the calculated centroid.')
	$toolTip.SetToolTip($createDigistarScriptsCheckBox, 'After a successful KML conversion, create matching Digistar on/off scripts from the local templates.')

	$fileNameGroupBox.Dock = 'Fill'
	$fileNameGroupBox.Text = 'Generated filename controls'
	$fileNameGroupBox.Padding = New-Object System.Windows.Forms.Padding(12, 24, 12, 12)
	$fileNameLayout.Dock = 'Fill'
	$fileNameLayout.ColumnCount = 1
	$fileNameLayout.RowCount = 4
	[void]$fileNameLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
	$fileNamePreviewLabel.Text = 'Preview: select an input and output location.'
	$fileNamePreviewLabel.AutoSize = $true
	$fileNamePreviewDetailLabel.Text = ''
	$fileNamePreviewDetailLabel.AutoSize = $true
	$fileNameInfoLabel.Text = 'Required base: <chosenStem>_<targetObject>_greatCircle. Folder mode uses each source filename as the stem.'
	$fileNameInfoLabel.AutoSize = $true
	$fileNameOptionsPanel.AutoSize = $true
	$fileNameOptionsPanel.FlowDirection = 'LeftToRight'
	$fileNameOptionsPanel.WrapContents = $false
	$fileNamePresetLabel.Text = 'Quick presets'
	$fileNamePresetLabel.AutoSize = $true
	$fileNamePresetLabel.Margin = New-Object System.Windows.Forms.Padding(0, 5, 12, 0)
	$presetNoneRadioButton.Text = 'None'
	$presetNoneRadioButton.AutoSize = $true
	$presetNoneRadioButton.Checked = $true
	$presetAllRadioButton.Text = 'All'
	$presetAllRadioButton.AutoSize = $true
	$targetRadiusSuffixCheckBox.Text = 'Target radius (trKm...)'
	$targetRadiusSuffixCheckBox.AutoSize = $true
	$anchorSuffixCheckBox.Text = 'Anchor point (not set)'
	$anchorSuffixCheckBox.AutoSize = $true
	[void]$fileNameOptionsPanel.Controls.Add($fileNamePresetLabel)
	[void]$fileNameOptionsPanel.Controls.Add($presetNoneRadioButton)
	[void]$fileNameOptionsPanel.Controls.Add($presetAllRadioButton)
	[void]$fileNameOptionsPanel.Controls.Add($targetRadiusSuffixCheckBox)
	[void]$fileNameOptionsPanel.Controls.Add($anchorSuffixCheckBox)
	[void]$fileNameLayout.Controls.Add($fileNamePreviewLabel, 0, 0)
	[void]$fileNameLayout.Controls.Add($fileNamePreviewDetailLabel, 0, 1)
	[void]$fileNameLayout.Controls.Add($fileNameInfoLabel, 0, 2)
	[void]$fileNameLayout.Controls.Add($fileNameOptionsPanel, 0, 3)
	[void]$fileNameGroupBox.Controls.Add($fileNameLayout)
	$toolTip.SetToolTip($fileNameGroupBox, 'The output filename always includes the chosen stem, target object, and greatCircle method.')
	$toolTip.SetToolTip($targetRadiusSuffixCheckBox, 'Append the effective target radius in kilometers to the generated filename.')
	$toolTip.SetToolTip($anchorSuffixCheckBox, 'Append the selected anchor latitude and longitude to the generated filename.')

	$logGroupBox.Dock = 'Fill'
	$logGroupBox.Text = 'Process log'
	$logGroupBox.Padding = New-Object System.Windows.Forms.Padding(12, 24, 12, 12)
	$logTextBox.Dock = 'Fill'
	$logTextBox.Multiline = $true
	$logTextBox.ReadOnly = $true
	$logTextBox.ScrollBars = 'Both'
	$logTextBox.WordWrap = $false
	[void]$logGroupBox.Controls.Add($logTextBox)

	[void]$pathSettingsSplitContainer.Panel1.Controls.Add($pathGroupBox)
	[void]$pathSettingsSplitContainer.Panel2.Controls.Add($settingsFileNameSplitContainer)
	[void]$settingsFileNameSplitContainer.Panel1.Controls.Add($optionsGroupBox)
	[void]$settingsFileNameSplitContainer.Panel2.Controls.Add($fileNameRunLogSplitContainer)
	[void]$fileNameRunLogSplitContainer.Panel1.Controls.Add($fileNameGroupBox)
	[void]$fileNameRunLogSplitContainer.Panel2.Controls.Add($logGroupBox)
	[void]$mainLayout.Controls.Add($headerLayout, 0, 0)
	[void]$mainLayout.Controls.Add($pathSettingsSplitContainer, 0, 1)
	[void]$form.Controls.Add($mainLayout)
	[void]$form.Controls.Add($menuStrip)

	$resolveTargetSettingsAction = ${function:Resolve-KmlConvertGuiTargetSettings}
	$convertRadiusTokenAction = ${function:Convert-KmlConvertGuiRadiusToFileNameToken}
	$convertAnchorTokenAction = ${function:Convert-KmlConvertGuiAnchorToFileNameToken}
	$resolveOutputPathAction = ${function:Resolve-KmlConvertGuiOutputPath}
	$newCliArgumentsAction = ${function:New-KmlConvertGuiCliArguments}
	$getNodeCommandAction = ${function:Get-KmlConvertGuiNodeCommand}
	$invokeCliProcessAction = ${function:Invoke-KmlConvertGuiCliProcess}
	$addLogTextAction = ${function:Add-KmlConvertGuiLogText}
	$setSplitterDistanceAction = ${function:Set-KmlConvertGuiSplitterDistance}
	$newAnchorMapFormPartsAction = ${function:New-KmlConvertGuiAnchorMapFormParts}
	$invokeDigistarScriptGenerationAction = ${function:Invoke-KmlConvertGuiDigistarScriptGeneration}
	$newBatchPlanAction = ${function:New-KmlConvertGuiBatchPlan}
	$invokeBatchConversionAction = ${function:Invoke-KmlConvertGuiBatchConversion}

	$setStatus = {
		param(
			[string]$StateName,
			[string]$StatusText
		)

		$statusLabel.Text = $StatusText

		if ($StateName -eq 'success') {
			$statusPanel.BackColor = [System.Drawing.Color]::Honeydew
			$statusLabel.ForeColor = [System.Drawing.Color]::DarkGreen
		} elseif ($StateName -eq 'failure') {
			$statusPanel.BackColor = [System.Drawing.Color]::MistyRose
			$statusLabel.ForeColor = [System.Drawing.Color]::DarkRed
		} elseif ($StateName -eq 'running') {
			$statusPanel.BackColor = [System.Drawing.Color]::LemonChiffon
			$statusLabel.ForeColor = [System.Drawing.Color]::Black
		} else {
			$statusPanel.BackColor = [System.Drawing.Color]::AliceBlue
			$statusLabel.ForeColor = [System.Drawing.Color]::MidnightBlue
		}
	}.GetNewClosure()

	$updateFont = {
		if ([Math]::Abs($form.Font.Size - $formState.BaseFontSize) -gt 0.01) {
			$newFont = New-Object System.Drawing.Font($form.Font.FontFamily, $formState.BaseFontSize)
			$newStatusFont = New-Object System.Drawing.Font($form.Font.FontFamily, ($formState.BaseFontSize + 1), [System.Drawing.FontStyle]::Bold)
			[void]$formState.OwnedFonts.Add($newFont)
			[void]$formState.OwnedFonts.Add($newStatusFont)

			$form.Font = $newFont
			$statusLabel.Font = $newStatusFont
		}

		$fontSizeValueLabel.Text = $formState.BaseFontSize.ToString('0')
		$decreaseFontButton.Enabled = ($formState.BaseFontSize -gt $formState.MinimumFontSize)
		$increaseFontButton.Enabled = ($formState.BaseFontSize -lt $formState.MaximumFontSize)
	}.GetNewClosure()

	$updateFileNamePreview = {
		$requestedOutputPath = $outputPathTextBox.Text.Trim()
		$inputPath = $inputPathTextBox.Text.Trim()

		if ($requestedOutputPath -eq '' -or $inputPath -eq '') {
			$fileNamePreviewLabel.Text = 'Preview: select an input and output location.'
			$fileNamePreviewDetailLabel.Text = ''
			return
		}

		try {
			$targetSettings = & $resolveTargetSettingsAction `
				-TargetObjectName ([string]$targetObjectComboBox.SelectedItem) `
				-TargetRadiusKmText $targetRadiusTextBox.Text
			$targetRadiusSuffixCheckBox.Text = 'Target radius (' + (& $convertRadiusTokenAction -RadiusKm $targetSettings.targetRadiusKm) + ')'
			$anchorSuffixCheckBox.Text = 'Anchor point (not set)'

			if (
				$anchorLatitudeTextBox.Text.Trim() -ne '' -or
				$anchorLongitudeTextBox.Text.Trim() -ne ''
			) {
				try {
					$anchorSuffixCheckBox.Text = (
						'Anchor point (' +
						(& $convertAnchorTokenAction `
							-AnchorLatitudeText $anchorLatitudeTextBox.Text `
							-AnchorLongitudeText $anchorLongitudeTextBox.Text) +
						')'
					)
				} catch {
					$anchorSuffixCheckBox.Text = 'Anchor point (invalid)'
				}
			}

			if ($folderModeRadioButton.Checked) {
				$batchPlan = & $newBatchPlanAction `
					-InputFolderPath $inputPath `
					-OutputFolderPath $requestedOutputPath `
					-Recursive $recursiveCheckBox.Checked `
					-TargetObjectName ([string]$targetObjectComboBox.SelectedItem) `
					-TargetRadiusKmText $targetRadiusTextBox.Text `
					-SourceRadiusKmText $sourceRadiusTextBox.Text `
					-AnchorLatitudeText $anchorLatitudeTextBox.Text `
					-AnchorLongitudeText $anchorLongitudeTextBox.Text `
					-IncludeTargetRadiusSuffix $targetRadiusSuffixCheckBox.Checked `
					-IncludeAnchorSuffix $anchorSuffixCheckBox.Checked `
					-CreateDigistarScripts $createDigistarScriptsCheckBox.Checked

				if ($batchPlan.Items.Count -eq 0) {
					$fileNamePreviewLabel.Text = 'Sample final filename: no eligible .kml file found.'
					$fileNamePreviewDetailLabel.Text = ''
					return
				}

				$fileNamePreviewLabel.Text = 'Sample final filename: ' + [System.IO.Path]::GetFileName($batchPlan.Items[0].OutputPath)
				$fileNamePreviewDetailLabel.Text = 'Sample source: ' + $batchPlan.Items[0].RelativeSourcePath
				return
			}

			$resolvedOutputPath = & $resolveOutputPathAction `
				-RequestedOutputPath $requestedOutputPath `
				-TargetObjectName ([string]$targetObjectComboBox.SelectedItem) `
				-TargetRadiusKmText $targetRadiusTextBox.Text `
				-IncludeTargetRadiusSuffix $targetRadiusSuffixCheckBox.Checked `
				-AnchorLatitudeText $anchorLatitudeTextBox.Text `
				-AnchorLongitudeText $anchorLongitudeTextBox.Text `
				-IncludeAnchorSuffix $anchorSuffixCheckBox.Checked
			$fileNamePreviewLabel.Text = 'Final filename: ' + [System.IO.Path]::GetFileName($resolvedOutputPath)
			$fileNamePreviewDetailLabel.Text = 'Output folder: ' + [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($resolvedOutputPath))
		} catch {
			$fileNamePreviewLabel.Text = 'Preview unavailable: ' + $_.Exception.Message
			$fileNamePreviewDetailLabel.Text = ''
		}
	}.GetNewClosure()

	$setAutomaticOutputPath = {
		$inputPath = $inputPathTextBox.Text.Trim()

		if ($inputPath -eq '') {
			return
		}

		if ($folderModeRadioButton.Checked) {
			if (-not (Test-Path -LiteralPath $inputPath -PathType Container)) {
				return
			}

			$inputFolder = Get-Item -LiteralPath $inputPath
			$automaticOutputPath = Join-Path $inputFolder.FullName ($inputFolder.Name + '_converted')
		} else {
			$inputDirectory = [System.IO.Path]::GetDirectoryName($inputPath)
			$inputStem = [System.IO.Path]::GetFileNameWithoutExtension($inputPath)

			if ($inputStem -eq '') {
				return
			}

			if ($inputDirectory -eq '') {
				$automaticOutputPath = $inputStem + '_converted.kml'
			} else {
				$automaticOutputPath = Join-Path $inputDirectory ($inputStem + '_converted.kml')
			}
		}

		$formState.IsUpdatingOutputPath = $true
		$outputPathTextBox.Text = $automaticOutputPath
		$formState.IsUpdatingOutputPath = $false
		$formState.IsOutputPathAutoManaged = $true
	}.GetNewClosure()

	$updateModeUi = {
		if ($folderModeRadioButton.Checked) {
			$inputPathLabel.Text = 'Input folder'
			$outputPathLabel.Text = 'Output folder'
			$recursiveCheckBox.Visible = $true
			$recursiveCheckBox.Enabled = $true
			$processButton.Text = 'Convert Folder'
			& $setStatus 'ready' 'Ready: folder batch mode.'
		} else {
			$inputPathLabel.Text = 'Input KML file'
			$outputPathLabel.Text = 'Output KML save path (chosen stem)'
			$recursiveCheckBox.Visible = $false
			$recursiveCheckBox.Enabled = $false
			$processButton.Text = 'Convert File'
			& $setStatus 'ready' 'Ready: single-file mode.'
		}
	}.GetNewClosure()

	$saveLayoutSettings = {
		try {
			$settingsDirectory = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($LayoutSettingsPath))

			if (-not (Test-Path -LiteralPath $settingsDirectory -PathType Container)) {
				[void](New-Item -ItemType Directory -Path $settingsDirectory -Force)
			}

			[pscustomobject]@{
				WindowLeft = $form.Bounds.Left
				WindowTop = $form.Bounds.Top
				WindowWidth = $form.Bounds.Width
				WindowHeight = $form.Bounds.Height
				PathSettingsSplitterDistance = $pathSettingsSplitContainer.SplitterDistance
				SettingsFileNameSplitterDistance = $settingsFileNameSplitContainer.SplitterDistance
				FileNameRunLogSplitterDistance = $fileNameRunLogSplitContainer.SplitterDistance
			} | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $LayoutSettingsPath -Encoding UTF8
		} catch {
			# Layout persistence must not block conversion or closing.
		}
	}.GetNewClosure()

	$inputPathTextBox.Add_TextChanged({
		if ($formState.IsOutputPathAutoManaged -or $outputPathTextBox.Text.Trim() -eq '') {
			& $setAutomaticOutputPath
		}

		& $updateFileNamePreview
	}.GetNewClosure())

	$outputPathTextBox.Add_TextChanged({
		if (-not $formState.IsUpdatingOutputPath) {
			$formState.IsOutputPathAutoManaged = ($outputPathTextBox.Text.Trim() -eq '')
		}

		& $updateFileNamePreview
	}.GetNewClosure())

	foreach ($control in @(
		$targetObjectComboBox,
		$targetRadiusTextBox,
		$sourceRadiusTextBox,
		$anchorLatitudeTextBox,
		$anchorLongitudeTextBox
	)) {
		$control.Add_TextChanged($updateFileNamePreview)
	}

	$targetObjectComboBox.Add_SelectedIndexChanged($updateFileNamePreview)
	$createDigistarScriptsCheckBox.Add_CheckedChanged($updateFileNamePreview)
	$recursiveCheckBox.Add_CheckedChanged($updateFileNamePreview)

	$singleFileModeRadioButton.Add_CheckedChanged({
		if ($singleFileModeRadioButton.Checked) {
			& $updateModeUi

			if ($formState.IsOutputPathAutoManaged) {
				& $setAutomaticOutputPath
			}

			& $updateFileNamePreview
		}
	}.GetNewClosure())

	$folderModeRadioButton.Add_CheckedChanged({
		if ($folderModeRadioButton.Checked) {
			& $updateModeUi

			if ($formState.IsOutputPathAutoManaged) {
				& $setAutomaticOutputPath
			}

			& $updateFileNamePreview
		}
	}.GetNewClosure())

	$presetNoneRadioButton.Add_CheckedChanged({
		if ($presetNoneRadioButton.Checked -and -not $formState.IsUpdatingSuffixControls) {
			$formState.IsUpdatingSuffixControls = $true
			$targetRadiusSuffixCheckBox.Checked = $false
			$anchorSuffixCheckBox.Checked = $false
			$formState.IsUpdatingSuffixControls = $false
			& $updateFileNamePreview
		}
	}.GetNewClosure())

	$presetAllRadioButton.Add_CheckedChanged({
		if ($presetAllRadioButton.Checked -and -not $formState.IsUpdatingSuffixControls) {
			$formState.IsUpdatingSuffixControls = $true
			$targetRadiusSuffixCheckBox.Checked = $true
			$anchorSuffixCheckBox.Checked = $true
			$formState.IsUpdatingSuffixControls = $false
			& $updateFileNamePreview
		}
	}.GetNewClosure())

	$targetRadiusSuffixCheckBox.Add_CheckedChanged({
		if (-not $formState.IsUpdatingSuffixControls) {
			$formState.IsUpdatingSuffixControls = $true
			$presetAllRadioButton.Checked = (
				$targetRadiusSuffixCheckBox.Checked -and
				$anchorSuffixCheckBox.Checked
			)
			$presetNoneRadioButton.Checked = (
				-not $targetRadiusSuffixCheckBox.Checked -and
				-not $anchorSuffixCheckBox.Checked
			)
			$formState.IsUpdatingSuffixControls = $false
		}

		& $updateFileNamePreview
	}.GetNewClosure())

	$anchorSuffixCheckBox.Add_CheckedChanged({
		if (-not $formState.IsUpdatingSuffixControls) {
			$formState.IsUpdatingSuffixControls = $true
			$presetAllRadioButton.Checked = (
				$targetRadiusSuffixCheckBox.Checked -and
				$anchorSuffixCheckBox.Checked
			)
			$presetNoneRadioButton.Checked = (
				-not $targetRadiusSuffixCheckBox.Checked -and
				-not $anchorSuffixCheckBox.Checked
			)
			$formState.IsUpdatingSuffixControls = $false
		}

		& $updateFileNamePreview
	}.GetNewClosure())

	$inputBrowseButton.Add_Click({
		if ($folderModeRadioButton.Checked) {
			$inputFolderDialog.Description = 'Select the folder containing KML files.'

			if (Test-Path -LiteralPath $inputPathTextBox.Text.Trim() -PathType Container) {
				$inputFolderDialog.SelectedPath = $inputPathTextBox.Text.Trim()
			}

			if ($inputFolderDialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
				$inputPathTextBox.Text = $inputFolderDialog.SelectedPath
			}

			return
		}

		$inputFileDialog.Filter = 'KML files (*.kml)|*.kml|All files (*.*)|*.*'
		$inputFileDialog.CheckFileExists = $true

		if ($inputFileDialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
			$inputPathTextBox.Text = $inputFileDialog.FileName
		}
	}.GetNewClosure())

	$outputBrowseButton.Add_Click({
		if ($folderModeRadioButton.Checked) {
			$outputFolderDialog.Description = 'Select the folder for converted KML files.'

			if (Test-Path -LiteralPath $outputPathTextBox.Text.Trim() -PathType Container) {
				$outputFolderDialog.SelectedPath = $outputPathTextBox.Text.Trim()
			}

			if ($outputFolderDialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
				$outputPathTextBox.Text = $outputFolderDialog.SelectedPath
			}

			return
		}

		$outputFileDialog.Filter = 'KML files (*.kml)|*.kml'
		$outputFileDialog.AddExtension = $true
		$outputFileDialog.DefaultExt = 'kml'
		$outputFileDialog.OverwritePrompt = $false

		if ($outputPathTextBox.Text.Trim() -ne '') {
			$outputFileDialog.FileName = $outputPathTextBox.Text
		}

		if ($outputFileDialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
			$outputPathTextBox.Text = $outputFileDialog.FileName
		}
	}.GetNewClosure())

	$inputFileMenuItem.Add_Click({
		$inputBrowseButton.PerformClick()
	}.GetNewClosure())

	$documentationMenuItem.Add_Click({
		if (Test-Path -LiteralPath $documentationFolderPath -PathType Container) {
			Start-Process -FilePath $documentationFolderPath
		} else {
			[void][System.Windows.Forms.MessageBox]::Show(
				$form,
				'Documentation folder not found: ' + $documentationFolderPath,
				'Documentation',
				[System.Windows.Forms.MessageBoxButtons]::OK,
				[System.Windows.Forms.MessageBoxIcon]::Information
			)
		}
	}.GetNewClosure())

	$quitMenuItem.Add_Click({
		$form.Close()
	}.GetNewClosure())

	$decreaseFontButton.Add_Click({
		if ($formState.BaseFontSize -gt $formState.MinimumFontSize) {
			$formState.BaseFontSize -= 1
			& $updateFont
		}
	}.GetNewClosure())

	$increaseFontButton.Add_Click({
		if ($formState.BaseFontSize -lt $formState.MaximumFontSize) {
			$formState.BaseFontSize += 1
			& $updateFont
		}
	}.GetNewClosure())

	$chooseAnchorMapButton.Add_Click({
		$anchorMapParts = $null

		try {
			$anchorMapParts = & $newAnchorMapFormPartsAction `
				-TargetObjectName ([string]$targetObjectComboBox.SelectedItem) `
				-AnchorLatitudeTextBox $anchorLatitudeTextBox `
				-AnchorLongitudeTextBox $anchorLongitudeTextBox
			[void]$anchorMapParts.Form.ShowDialog($form)
		} finally {
			if ($null -ne $anchorMapParts -and -not $anchorMapParts.Form.IsDisposed) {
				$anchorMapParts.Form.Dispose()
			}
		}
	}.GetNewClosure())

	$clearAnchorButton.Add_Click({
		$anchorLatitudeTextBox.Clear()
		$anchorLongitudeTextBox.Clear()
	}.GetNewClosure())

	$processButton.Add_Click({
		$cliArguments = @()
		$resolvedOutputPath = ''
		$dialogResult = [System.Windows.Forms.DialogResult]::None
		$nodeCommandPath = ''
		$processResult = $null
		$digistarScriptResult = $null

		try {
			if ($folderModeRadioButton.Checked) {
				$batchPlan = & $newBatchPlanAction `
					-InputFolderPath $inputPathTextBox.Text `
					-OutputFolderPath $outputPathTextBox.Text `
					-Recursive $recursiveCheckBox.Checked `
					-TargetObjectName ([string]$targetObjectComboBox.SelectedItem) `
					-TargetRadiusKmText $targetRadiusTextBox.Text `
					-SourceRadiusKmText $sourceRadiusTextBox.Text `
					-AnchorLatitudeText $anchorLatitudeTextBox.Text `
					-AnchorLongitudeText $anchorLongitudeTextBox.Text `
					-IncludeTargetRadiusSuffix $targetRadiusSuffixCheckBox.Checked `
					-IncludeAnchorSuffix $anchorSuffixCheckBox.Checked `
					-CreateDigistarScripts $createDigistarScriptsCheckBox.Checked
				$allowBatchOverwrite = $false

				if ($batchPlan.ExistingOutputPaths.Count -gt 0) {
					$dialogResult = [System.Windows.Forms.MessageBox]::Show(
						$form,
						(
							$batchPlan.ExistingOutputPaths.Count.ToString() +
							' generated output path(s) already exist.' +
							[System.Environment]::NewLine +
							'Choose Yes to replace them. Choose No to skip them.'
						),
						'Confirm batch overwrite',
						[System.Windows.Forms.MessageBoxButtons]::YesNo,
						[System.Windows.Forms.MessageBoxIcon]::Warning
					)
					$allowBatchOverwrite = (
						$dialogResult -eq [System.Windows.Forms.DialogResult]::Yes
					)
				}

				$nodeCommandPath = & $getNodeCommandAction
				$formState.IsRunning = $true
				$processButton.Enabled = $false
				$quitMenuItem.Enabled = $false
				$processButton.Text = 'Running...'
				& $setStatus 'running' 'Running folder batch conversion...'
				& $addLogTextAction -LogTextBox $logTextBox -TextToAppend ''
				& $addLogTextAction -LogTextBox $logTextBox -TextToAppend (
					'Batch: ' +
					$batchPlan.Items.Count.ToString() +
					' eligible KML file(s).'
				)
				[System.Windows.Forms.Application]::DoEvents()
				$batchResult = & $invokeBatchConversionAction `
					-BatchPlan $batchPlan `
					-NodeCommandPath $nodeCommandPath `
					-DigistarTemplateDirectory $DigistarTemplateDirectory `
					-AllowOverwrite $allowBatchOverwrite

				foreach ($batchItemResult in $batchResult.Items) {
					if ($batchItemResult.Status -eq 'converted') {
						$batchLogText = (
							'PASS: ' +
							$batchItemResult.SourcePath +
							' -> ' +
							$batchItemResult.OutputPath
						)

						if ($batchItemResult.OnScriptPath -ne '') {
							$batchLogText += (
								' | Digistar: ' +
								$batchItemResult.OnScriptPath +
								'; ' +
								$batchItemResult.OffScriptPath
							)
						}
					} elseif ($batchItemResult.Status -eq 'skipped') {
						$batchLogText = (
							'SKIP: ' +
							$batchItemResult.SourcePath +
							' | ' +
							$batchItemResult.Message
						)
					} else {
						$batchLogText = (
							'FAIL: ' +
							$batchItemResult.SourcePath +
							' | ' +
							$batchItemResult.Message
						)
					}

					& $addLogTextAction -LogTextBox $logTextBox -TextToAppend $batchLogText
				}

				$batchSummaryText = (
					'Summary: converted ' +
					$batchResult.ConvertedCount.ToString() +
					', failed ' +
					$batchResult.FailedCount.ToString() +
					', skipped ' +
					$batchResult.SkippedCount.ToString() +
					'.'
				)
				& $addLogTextAction -LogTextBox $logTextBox -TextToAppend $batchSummaryText

				if ($batchResult.OverallSuccess) {
					& $setStatus 'success' ('PASS: ' + $batchSummaryText)
				} else {
					& $setStatus 'failure' ('FAIL: ' + $batchSummaryText)
				}

				return
			}

			$cliArguments = & $newCliArgumentsAction `
				-InputPath $inputPathTextBox.Text `
				-OutputPath $outputPathTextBox.Text `
				-TargetObjectName ([string]$targetObjectComboBox.SelectedItem) `
				-TargetRadiusKmText $targetRadiusTextBox.Text `
				-SourceRadiusKmText $sourceRadiusTextBox.Text `
				-AnchorLatitudeText $anchorLatitudeTextBox.Text `
				-AnchorLongitudeText $anchorLongitudeTextBox.Text `
				-IncludeTargetRadiusSuffix $targetRadiusSuffixCheckBox.Checked `
				-IncludeAnchorSuffix $anchorSuffixCheckBox.Checked
			$resolvedOutputPath = $cliArguments[4]

			if (Test-Path -LiteralPath $resolvedOutputPath -PathType Leaf) {
				$dialogResult = [System.Windows.Forms.MessageBox]::Show(
					$form,
					'The generated output already exists. Replace it?' + [System.Environment]::NewLine + $resolvedOutputPath,
					'Confirm overwrite',
					[System.Windows.Forms.MessageBoxButtons]::YesNo,
					[System.Windows.Forms.MessageBoxIcon]::Warning
				)

				if ($dialogResult -ne [System.Windows.Forms.DialogResult]::Yes) {
					& $setStatus 'ready' 'Ready: conversion cancelled.'
					return
				}
			}

			$nodeCommandPath = & $getNodeCommandAction
			$formState.IsRunning = $true
			$processButton.Enabled = $false
			$quitMenuItem.Enabled = $false
			$processButton.Text = 'Running...'
			& $setStatus 'running' 'Running conversion...'
			& $addLogTextAction -LogTextBox $logTextBox -TextToAppend ''
			& $addLogTextAction -LogTextBox $logTextBox -TextToAppend ('Node command: ' + $nodeCommandPath)
			& $addLogTextAction -LogTextBox $logTextBox -TextToAppend 'CLI arguments:'

			foreach ($cliArgument in $cliArguments) {
				& $addLogTextAction -LogTextBox $logTextBox -TextToAppend ('  ' + $cliArgument)
			}

			[System.Windows.Forms.Application]::DoEvents()
			$processResult = & $invokeCliProcessAction -NodeCommandPath $nodeCommandPath -CliArguments $cliArguments

			if ($processResult.StandardOutput.Trim() -ne '') {
				& $addLogTextAction -LogTextBox $logTextBox -TextToAppend 'STDOUT:'
				& $addLogTextAction -LogTextBox $logTextBox -TextToAppend $processResult.StandardOutput.TrimEnd()
			}

			if ($processResult.StandardError.Trim() -ne '') {
				& $addLogTextAction -LogTextBox $logTextBox -TextToAppend 'STDERR:'
				& $addLogTextAction -LogTextBox $logTextBox -TextToAppend $processResult.StandardError.TrimEnd()
			}

			if ($processResult.ExitCode -eq 0 -and (Test-Path -LiteralPath $resolvedOutputPath -PathType Leaf)) {
				$digistarScriptResult = & $invokeDigistarScriptGenerationAction `
					-Enabled $createDigistarScriptsCheckBox.Checked `
					-ConvertedKmlPath $resolvedOutputPath `
					-OriginalKmlPath $inputPathTextBox.Text `
					-TargetObjectName ([string]$targetObjectComboBox.SelectedItem) `
					-TargetRadiusKmText $targetRadiusTextBox.Text `
					-TemplateDirectory $DigistarTemplateDirectory

				if ($null -ne $digistarScriptResult) {
					& $addLogTextAction -LogTextBox $logTextBox -TextToAppend ('Digistar on script: ' + $digistarScriptResult.OnScriptPath)
					& $addLogTextAction -LogTextBox $logTextBox -TextToAppend ('Digistar off script: ' + $digistarScriptResult.OffScriptPath)
					& $setStatus 'success' ('PASS: Converted KML and created Digistar scripts for ' + [System.IO.Path]::GetFileName($resolvedOutputPath))
				} else {
					& $setStatus 'success' ('PASS: Converted ' + [System.IO.Path]::GetFileName($resolvedOutputPath))
				}
			} else {
				& $setStatus 'failure' ('FAIL: Node process exited with code ' + $processResult.ExitCode + '.')
			}
		} catch {
			& $addLogTextAction -LogTextBox $logTextBox -TextToAppend ('FAIL: ' + $_.Exception.Message)
			& $setStatus 'failure' ('FAIL: ' + $_.Exception.Message)
		} finally {
			$formState.IsRunning = $false
			$processButton.Enabled = $true
			$quitMenuItem.Enabled = $true

			if ($folderModeRadioButton.Checked) {
				$processButton.Text = 'Convert Folder'
			} else {
				$processButton.Text = 'Convert File'
			}
		}
	}.GetNewClosure())

	$form.Add_FormClosing({
		param($sender, $eventArgs)

		if ($formState.IsRunning) {
			$eventArgs.Cancel = $true
			[void][System.Windows.Forms.MessageBox]::Show(
				$form,
				'Wait for the current conversion to finish before closing.',
				'Conversion running',
				[System.Windows.Forms.MessageBoxButtons]::OK,
				[System.Windows.Forms.MessageBoxIcon]::Information
			)
			return
		}

		& $saveLayoutSettings
	}.GetNewClosure())

	$form.Add_Disposed({
		foreach ($ownedFont in $formState.OwnedFonts) {
			$ownedFont.Dispose()
		}

		$formState.OwnedFonts.Clear()
	}.GetNewClosure())

	$form.Add_Shown({
		& $setSplitterDistanceAction -SplitContainer $pathSettingsSplitContainer -RequestedDistance 205
		& $setSplitterDistanceAction -SplitContainer $settingsFileNameSplitContainer -RequestedDistance 270
		& $setSplitterDistanceAction -SplitContainer $fileNameRunLogSplitContainer -RequestedDistance 150

		if (Test-Path -LiteralPath $LayoutSettingsPath -PathType Leaf) {
			try {
				$layoutSettings = Get-Content -LiteralPath $LayoutSettingsPath -Raw | ConvertFrom-Json

				if (
					[int]$layoutSettings.WindowWidth -ge $form.MinimumSize.Width -and
					[int]$layoutSettings.WindowHeight -ge $form.MinimumSize.Height
				) {
					$form.SetBounds(
						[int]$layoutSettings.WindowLeft,
						[int]$layoutSettings.WindowTop,
						[int]$layoutSettings.WindowWidth,
						[int]$layoutSettings.WindowHeight
					)
				}

				& $setSplitterDistanceAction -SplitContainer $pathSettingsSplitContainer -RequestedDistance ([int]$layoutSettings.PathSettingsSplitterDistance)
				& $setSplitterDistanceAction -SplitContainer $settingsFileNameSplitContainer -RequestedDistance ([int]$layoutSettings.SettingsFileNameSplitterDistance)
				& $setSplitterDistanceAction -SplitContainer $fileNameRunLogSplitContainer -RequestedDistance ([int]$layoutSettings.FileNameRunLogSplitterDistance)
			} catch {
				& $addLogTextAction -LogTextBox $logTextBox -TextToAppend 'Ignored invalid layoutSettings.json.'
			}
		}
	}.GetNewClosure())

	& $updateModeUi
	& $updateFont
	& $updateFileNamePreview

	return [pscustomobject]@{
		Form = $form
		ToolTip = $toolTip
		MenuStrip = $menuStrip
		FileMenuItem = $fileMenuItem
		HelpMenuItem = $helpMenuItem
		FontSizeLabel = $fontSizeLabel
		InputFileMenuItem = $inputFileMenuItem
		DocumentationMenuItem = $documentationMenuItem
		QuitMenuItem = $quitMenuItem
		DocumentationFolderPath = $documentationFolderPath
		LayoutSettingsPath = $LayoutSettingsPath
		InputPathTextBox = $inputPathTextBox
		OutputPathTextBox = $outputPathTextBox
		InputBrowseButton = $inputBrowseButton
		OutputBrowseButton = $outputBrowseButton
		SingleFileModeRadioButton = $singleFileModeRadioButton
		FolderModeRadioButton = $folderModeRadioButton
		RecursiveCheckBox = $recursiveCheckBox
		TargetObjectComboBox = $targetObjectComboBox
		TargetRadiusTextBox = $targetRadiusTextBox
		SourceRadiusTextBox = $sourceRadiusTextBox
		AnchorLatitudeTextBox = $anchorLatitudeTextBox
		AnchorLongitudeTextBox = $anchorLongitudeTextBox
		ChooseAnchorMapButton = $chooseAnchorMapButton
		ClearAnchorButton = $clearAnchorButton
		CreateDigistarScriptsCheckBox = $createDigistarScriptsCheckBox
		DigistarTemplateDirectory = $DigistarTemplateDirectory
		OptionsGroupBox = $optionsGroupBox
		FileNameGroupBox = $fileNameGroupBox
		FileNamePreviewLabel = $fileNamePreviewLabel
		FileNamePreviewDetailLabel = $fileNamePreviewDetailLabel
		PresetNoneRadioButton = $presetNoneRadioButton
		PresetAllRadioButton = $presetAllRadioButton
		TargetRadiusSuffixCheckBox = $targetRadiusSuffixCheckBox
		AnchorSuffixCheckBox = $anchorSuffixCheckBox
		HeaderLayout = $headerLayout
		ProcessButton = $processButton
		DecreaseFontButton = $decreaseFontButton
		IncreaseFontButton = $increaseFontButton
		FontSizeValueLabel = $fontSizeValueLabel
		StatusPanel = $statusPanel
		StatusLabel = $statusLabel
		LogTextBox = $logTextBox
		PathSettingsSplitContainer = $pathSettingsSplitContainer
		SettingsFileNameSplitContainer = $settingsFileNameSplitContainer
		FileNameRunLogSplitContainer = $fileNameRunLogSplitContainer
	}
}

function Show-KmlConvertGui {
	$guiFormParts = New-KmlConvertGuiFormParts

	[void]$guiFormParts.Form.ShowDialog()
}

if ($MyInvocation.InvocationName -ne '.') {
	Show-KmlConvertGui
}
