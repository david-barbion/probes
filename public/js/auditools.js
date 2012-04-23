$(function () {

    jQuery.auditools = {
        data: [],
    };

    function drawGraph(from, to) {

        var data = [];
        var options = {
            legend: {
                show: ($('input[name=show-legend]:checked').length == 1),
                noColumns: $('input[name=legend-cols]').val()
            },
            series: {
                stack: ($('#stacked:checked').length == 1? true:null),
            },
            xaxis: {
		mode: 'time',
		timeformat: "%d/%m/%y %H:%M:%S"
	    },
            selection: {
                mode: "x",
                color: "#444"
            }
        }

	/* disable form submission when using enter in flot options text fields */
	$('#series-width').keypress(function(event) {
	    if ( event.which == 13 ) return false;
	});

	$('#legend-cols').keypress(function(event) {
	    if ( event.which == 13 ) return false;
	});

        if ($('input[name=graph-type]:checked').val() == 'lines') {
            options['series']['lines'] = {
                show: true,
                fill: ($('#filled:checked').length == 1),
                lineWidth: parseFloat($('input[name=series-width]').val())
            };
        }
        else if ($('input[name=graph-type]:checked').val() == 'points') {
            options['series']['points'] = {
                show: true,
                fill: ($('#filled:checked').length == 1),
                radius: parseFloat($('input[name=series-width]').val())
            };
        }
        else {
            options['series']['pie'] = {
                show: true,
            };
        }

        if (from != null)
            options['xaxis'].min = from;

        if (to != null)
            options['xaxis'].max = to;

        $('#legend').find("input:checked").each(function () {
            var key = $(this).attr("name").substring(6);
            if (jQuery.auditools.data[key])
                data.push(jQuery.auditools.data[key]);
        });

        if (!data.length)
            data = jQuery.auditools.data;

        var plot = $.plot(
            $('#graph_area'),
            data,
            options
        );

        //$('div.legend').draggable();
        $('#graph_box')
            //.draggable({handle: $('.tickLabel')})
            .resizable({
                helper: 'resize-hi',
                stop: function () {
                    drawGraph();
                }
            });

        return plot;
    }

    /* update the graph when changing properties */
    $('#form input:checkbox').click(function () {
       drawGraph();
    });
    $('input[name=legend-cols]').change(function () {
       drawGraph();
    });
    
    $('#add_graph').click(function () {
        $.ajax({
            url: '/draw/data',
            type: 'post',
            dataType: 'json',
            data: {
                query: $('#query').val(),
		nsp: $('input[name=nsp]').val()
            },
            success: function (series) {
                if (series.error != null) {
                    alert("error:" + series.error);
                    return;
                }

                jQuery.auditools.data = series;

                /* Hardcode the color for each series so they don't change
                   when enabling/disabling and moving them. */
                var i = 0;
                $.each(jQuery.auditools.data, function(key, val) {
                    val.color = i;
                    i++;
                });

                var plot = drawGraph();

                /* build the dynamic legend */
                $('#legend').empty();
                $.each(plot.getData(), function(idx, val) {
                    $('#legend').append('<li class="sortable">'
                        + '<div class="legend-color" id="color-' + idx + '">'
                        + '<div style="background-color: '+ val.color +'"></div></div>'
                        + '<label for="id-serie-' + idx + '">'
                        + '<input type="checkbox" name="serie-'+ idx +'" checked="checked" id="id-serie-'+ idx +'" />'
                        + val.label + '</label></li>');
                });

// <div style="border:1px solid #ccc;padding:1px">
// <div style="width:4px;height:0;border:5px solid rgb(237,194,64);overflow:hidden"></div>
// </div>


                /* make the legend sortable */
                if (jQuery.auditools.data.length) {
                    $('#legend')
                        .sortable({
                            update: function(event, ui) {
                                drawGraph();
                            },
                            placeholder: "drag-hi"
                        })
                        .disableSelection();
                }

                /* update the graph with selected series */
                $('#legend').find("input:checkbox").click(function () {
                    drawGraph();
                });
            }
        });
        return false;
    });

    /* handle zoom action */
    $('#graph_area').bind("plotselected", function (event, ranges) {

        // clamp the zooming to prevent eternal zoom
        if (ranges.xaxis.to - ranges.xaxis.from < 0.00001) 
            ranges.xaxis.to = ranges.xaxis.from + 0.00001;
        if (ranges.yaxis.to - ranges.yaxis.from < 0.00001) 
            ranges.yaxis.to = ranges.yaxis.from + 0.00001;

        drawGraph(ranges.xaxis.from.toPrecision(13), ranges.xaxis.to.toPrecision(13));
    });

    $('div#presets select').change(function () {
	$('#query').text($(this).val());
    });

    drawGraph();
});