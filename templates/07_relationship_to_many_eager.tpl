{{- if .Table.IsJoinTable -}}
{{- else -}}
{{- $dot := . -}}
{{- range .Table.ToManyRelationships -}}
{{- if (and .ForeignColumnUnique (not .ToJoinTable)) -}}
  {{- template "relationship_to_one_eager_helper" (textsFromOneToOneRelationship $dot.PkgName $dot.Tables $dot.Table .) -}}
{{- else -}}
  {{- $rel := textsFromRelationship $dot.Tables $dot.Table . -}}
  {{- $arg := printf "maybe%s" $rel.LocalTable.NameGo -}}
  {{- $slice := printf "%sSlice" $rel.LocalTable.NameGo -}}
// Load{{$rel.Function.Name}} allows an eager lookup of values, cached into the
// loaded structs of the objects.
func (r *{{$rel.LocalTable.NameGo}}Loaded) Load{{$rel.Function.Name}}(e boil.Executor, singular bool, {{$arg}} interface{}) error {
  var slice []*{{$rel.LocalTable.NameGo}}
  var object *{{$rel.LocalTable.NameGo}}

  count := 1
  if singular {
    object = {{$arg}}.(*{{$rel.LocalTable.NameGo}})
  } else {
    slice = *{{$arg}}.(*{{$slice}})
    count = len(slice)
  }

  args := make([]interface{}, count)
  if singular {
    args[0] = object.{{.Column | titleCase}}
  } else {
    for i, obj := range slice {
      args[i] = obj.{{.Column | titleCase}}
    }
  }

    {{if .ToJoinTable -}}
  query := fmt.Sprintf(
    `select "{{id 0}}".*, "{{id 1}}"."{{.JoinLocalColumn}}" from "{{.ForeignTable}}" as "{{id 0}}" inner join "{{.JoinTable}}" as "{{id 1}}" on "{{id 0}}"."{{.ForeignColumn}}" = "{{id 1}}"."{{.JoinForeignColumn}}" where "{{id 1}}"."{{.JoinLocalColumn}}" in (%s)`,
    strmangle.Placeholders(count, 1, 1),
  )
    {{else -}}
  query := fmt.Sprintf(
    `select * from "{{.ForeignTable}}" where "{{.ForeignColumn}}" in (%s)`,
    strmangle.Placeholders(count, 1, 1),
  )
    {{end -}}

  if boil.DebugMode {
    fmt.Fprintf(boil.DebugWriter, "%s\n%v\n", query, args)
  }

  results, err := e.Query(query, args...)
  if err != nil {
    return errors.Wrap(err, "failed to eager load {{.ForeignTable}}")
  }
  defer results.Close()

  var resultSlice []*{{$rel.ForeignTable.NameGo}}
  {{if .ToJoinTable -}}
  {{- $foreignTable := getTable $dot.Tables .ForeignTable -}}
  {{- $joinTable := getTable $dot.Tables .JoinTable -}}
  {{- $localCol := $joinTable.GetColumn .JoinLocalColumn}}
  var localJoinCols []{{$localCol.Type}}
  for results.Next() {
    one := new({{$rel.ForeignTable.NameGo}})
    var localJoinCol {{$localCol.Type}}

    err = results.Scan({{$foreignTable.Columns | columnNames | stringMap $dot.StringFuncs.titleCase | prefixStringSlice "&one." | join ", "}}, &localJoinCol)
    if err = results.Err(); err != nil {
      return errors.Wrap(err, "failed to plebian-bind eager loaded slice {{.ForeignTable}}")
    }

    resultSlice = append(resultSlice, one)
    localJoinCols = append(localJoinCols, localJoinCol)
  }

  if err = results.Err(); err != nil {
    return errors.Wrap(err, "failed to plebian-bind eager loaded slice {{.ForeignTable}}")
  }
  {{else -}}
  if err = boil.BindFast(results, &resultSlice, {{$dot.Table.Name | singular | camelCase}}TitleCases); err != nil {
    return errors.Wrap(err, "failed to bind eager loaded slice {{.ForeignTable}}")
  }
  {{end}}

  if singular {
    if object.Loaded == nil {
      object.Loaded = &{{$rel.LocalTable.NameGo}}Loaded{}
    }
    object.Loaded.{{$rel.Function.Name}} = resultSlice
    return nil
  }

  {{if .ToJoinTable -}}
  for i, foreign := range resultSlice {
    localJoinCol := localJoinCols[i]
    for _, local := range slice {
      if local.{{$rel.Function.LocalAssignment}} == localJoinCol {
        if local.Loaded == nil {
          local.Loaded = &{{$rel.LocalTable.NameGo}}Loaded{}
        }
        local.Loaded.{{$rel.Function.Name}} = append(local.Loaded.{{$rel.Function.Name}}, foreign)
        break
      }
    }
  }
  {{else -}}
  for _, foreign := range resultSlice {
    for _, local := range slice {
      if local.{{$rel.Function.LocalAssignment}} == foreign.{{$rel.Function.ForeignAssignment}} {
        if local.Loaded == nil {
          local.Loaded = &{{$rel.LocalTable.NameGo}}Loaded{}
        }
        local.Loaded.{{$rel.Function.Name}} = append(local.Loaded.{{$rel.Function.Name}}, foreign)
        break
      }
    }
  }
  {{end}}

  return nil
}

{{end -}}{{/* if ForeignColumnUnique */}}
{{- end -}}{{/* range tomany */}}
{{- end -}}{{/* if isjointable */}}