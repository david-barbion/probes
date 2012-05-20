$(function () {

    jQuery.auditools = {
        data: [],
	scale: {}
    };

    

    function drawGraph(opts) {

        var data = [];
        var options = {
            legend: {
                show: ($('input[name=show-legend]:checked').length == 1),
                noColumns: $('input[name=legend-cols]').val(),
		position: 'ne',
            },
	    xaxis: {
		mode: 'time',
		timeFormat: "%d/%m/%y %H:%M:%S",
		min: null, max: null, autoscale: true },
	    yaxis: {
		min: null, max: null, autoscale: true },
	    title: $('#name').val() || null,
	    subtitle : $('#desc').val() || null,
            selection: {
                mode: "xy"
            }
        }
	options = Flotr._.extend(options, jQuery.auditools.scale);

	/* disable form submission when using enter in flot options text fields */
	$('#series-width').keypress(function(event) {
	    if ( event.which == 13 ) return false;
	});

	$('#legend-cols').keypress(function(event) {
	    if ( event.which == 13 ) return false;
	});

        if ($('input[name=graph-type]:checked').val() == 'lines') {
	    delete options.points;
	    delete options.pie;
            options['lines'] = {
                show: true,
                fill: ($('#filled:checked').length == 1),
                lineWidth: parseFloat($('input[name=series-width]').val()),
		stacked: ($('#stacked:checked').length == 1? true:null)
            };
        }
        else if ($('input[name=graph-type]:checked').val() == 'points') {
	    delete options.lines;
	    delete options.pie;
            options['points'] = {
                show: true,
                fill: ($('#filled:checked').length == 1),
                lineWidth: parseFloat($('input[name=series-width]').val()),
		stacked: ($('#stacked:checked').length == 1? true:null)
            };
        }
        else {
	    delete options.lines;
	    delete options.points;
            options['pie'] = {
                show: true,
		fill: ($('#filled:checked').length == 1),
                lineWidth: parseFloat($('input[name=series-width]').val()),
		stacked: ($('#stacked:checked').length == 1? true:null)
            };
        }

        if (!data.length)
            data = jQuery.auditools.data;

        return graph = Flotr.draw(
            $('#graph_area').get(0),
            data,
            Flotr._.extend(Flotr._.clone(options), opts || {})
        );

    }

    /* update the graph when changing properties */
    $('#form input[type="checkbox"]').change(function () {
       drawGraph();
    });
    $('#form input[type="radio"]').change(function () {
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

                jQuery.auditools.data = series['data'];
		jQuery.auditools.scale = { 
		    xaxis: {
			mode: 'time',
			timeFormat: "%d/%m/%y %H:%M:%S",
			min: series['scale']['xmin'],
			max: series['scale']['xmax']
		    },
		    yaxis: {
			min: (parseInt(series['scale']['ymin']) >= 0) ? 0 : series['scale']['ymin'],
			max: series['scale']['ymax']
		    }
		};

		drawGraph();
			   
            }
        });
        return false;
    });

    /* update the query textarea when a preset option is selected */
    $('li#presets select').change(function () {
	$('#query').text($(this).val());
    });
});
