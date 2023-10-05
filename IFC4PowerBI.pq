// IFC4PowerBI
// GPL3.0 License
// Created by Shift @ shift-construction.com
// Github: https://github.com/shift-construction/ifc4PowerBI

let
    Source = (#"IFC File" as any) => let
      // Initial Import
      Source = Table.FromColumns({Lines.FromBinary(#"IFC File", null, null, 1252)}), 
      // Split by Equal Sign
      SplitByEquals = Table.SplitColumn(
        Source, 
        "Column1", 
        Splitter.SplitTextByEachDelimiter({"="}, QuoteStyle.Csv, false), 
        {"Element ID", "Values"}
      ), 
      // Replace Single Quotes
      ReplaceSingleQuotes = Table.ReplaceValue(
        SplitByEquals, 
        "'", 
        """", 
        Replacer.ReplaceText, 
        {"Values"}
      ), 
      // Trim Text
      TrimValues = Table.TransformColumns(
        ReplaceSingleQuotes, 
        {{"Values", Text.Trim, type text}, {"Element ID", Text.Trim, type text}}
      ), 
      // Filter Non-null Rows
      FilterNonNullValues = Table.SelectRows(TrimValues, each ([Values] <> null)), 
      // Split by Open Parenthesis
      SplitByOpenParenthesis = Table.SplitColumn(
        FilterNonNullValues, 
        "Values", 
        Splitter.SplitTextByEachDelimiter({"("}, QuoteStyle.None, false), 
        {"Category", "Values"}
      ), 
      // Extract Data Before Close Parenthesis
      ExtractBeforeCloseParenthesis = Table.TransformColumns(
        SplitByOpenParenthesis, 
        {{"Values", each Text.BeforeDelimiter(_, ")", {0, RelativePosition.FromEnd}), type text}}
      ), 
      // Filtering & Transformation for IFCPROPERTYSINGLEVALUE
      FilterSingleValue = Table.SelectRows(
        ExtractBeforeCloseParenthesis, 
        each ([Category] = "IFCPROPERTYSINGLEVALUE")
      ), 
      SplitSingleValueDetails = Table.SplitColumn(
        FilterSingleValue, 
        "Values", 
        Splitter.SplitTextByDelimiter(",", QuoteStyle.Csv), 
        {"Property Name", "Property Description", "Property Value", "Property Unit"}
      ), 
      ExtractSingleValue = Table.TransformColumns(
        SplitSingleValueDetails, 
        {{"Property Value", each Text.BetweenDelimiters(_, "(", ")"), type text}}
      ), 
      // Filtering & Transformation for IFCPROPERTYSET
      FilterPropertySet = Table.SelectRows(
        ExtractBeforeCloseParenthesis, 
        each [Category] = "IFCPROPERTYSET"
      ), 
      ExtractPropertyID = Table.AddColumn(
        FilterPropertySet, 
        "Property ID", 
        each Text.BetweenDelimiters([Values], "(", ")"), 
        type text
      ), 
      ExtractPsetName = Table.TransformColumns(
        ExtractPropertyID, 
        {{"Values", each Text.BetweenDelimiters(_, ",", ",", 1, 0), type text}}
      ), 
      RemoveQuotes = Table.ReplaceValue(ExtractPsetName, """", "", Replacer.ReplaceText, {"Values"}), 
      ExpandPropertyID = Table.ExpandListColumn(
        Table.TransformColumns(
          RemoveQuotes, 
          {
            {
              "Property ID", 
              Splitter.SplitTextByDelimiter(",", QuoteStyle.Csv), 
              let
                itemType = (type nullable text) meta [Serialized.Text = true]
              in
                type {itemType}
            }
          }
        ), 
        "Property ID"
      ), 
      RenamePsetColumns = Table.RenameColumns(ExpandPropertyID, {{"Values", "Pset Name"}}), 
      JoinSingleValueAndPset = Table.NestedJoin(
        RenamePsetColumns, 
        {"Property ID"}, 
        ExtractSingleValue, 
        {"Element ID"}, 
        "Properties", 
        JoinKind.LeftOuter
      ), 
      ExpandProperties = Table.ExpandTableColumn(
        JoinSingleValueAndPset, 
        "Properties", 
        {"Property Name", "Property Value"}, 
        {"Property Name", "Property Value"}
      ), 
      // Filtering & Transformation for IFCRELDEFINESBYPROPERTIES
      FilterRelDefines = Table.SelectRows(
        ExtractBeforeCloseParenthesis, 
        each [Category] = "IFCRELDEFINESBYPROPERTIES"
      ), 
      ExtractObjectID = Table.AddColumn(
        FilterRelDefines, 
        "Object ID", 
        each Text.BetweenDelimiters([Values], "(", ")", {0, RelativePosition.FromEnd}, 0), 
        type text
      ), 
      ExtractPsetID = Table.TransformColumns(
        ExtractObjectID, 
        {{"Values", each Text.AfterDelimiter(_, ",", {0, RelativePosition.FromEnd}), type text}}
      ), 
      RenameForRelDefines = Table.RenameColumns(ExtractPsetID, {{"Values", "Pset ID"}}), 
      ExpandObjectID = Table.ExpandListColumn(
        Table.TransformColumns(
          RenameForRelDefines, 
          {
            {
              "Object ID", 
              Splitter.SplitTextByDelimiter(",", QuoteStyle.Csv), 
              let
                itemType = (type nullable text) meta [Serialized.Text = true]
              in
                type {itemType}
            }
          }
        ), 
        "Object ID"
      ), 
      JoinRelDefinesAndPset = Table.NestedJoin(
        ExpandObjectID, 
        {"Pset ID"}, 
        ExpandProperties, 
        {"Element ID"}, 
        "Property Sets", 
        JoinKind.LeftOuter
      ), 
      ExpandPropertySets = Table.ExpandTableColumn(
        JoinRelDefinesAndPset, 
        "Property Sets", 
        {"Pset Name", "Property Name", "Property Value"}, 
        {"Pset Name", "Property Name", "Property Value"}
      ), 
      // Final Join and Expansion
      JoinMain = Table.NestedJoin(
        ExpandPropertySets, 
        {"Object ID"}, 
        ExtractBeforeCloseParenthesis, 
        {"Element ID"}, 
        "Model", 
        JoinKind.LeftOuter
      ), 
      ExpandModel = Table.ExpandTableColumn(
        JoinMain, 
        "Model", 
        {"Category", "Values"}, 
        {"Ifc Type", "Values"}
      ), 
      FinalSplit = Table.SplitColumn(
        ExpandModel, 
        "Values", 
        Splitter.SplitTextByDelimiter(",", QuoteStyle.Csv), 
        {"GUID"}
      )
    in
      FinalSplit
in
    Source